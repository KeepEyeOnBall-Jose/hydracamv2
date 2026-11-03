#!/usr/bin/env python3
"""Userspace shared-uplink emulator for the H8 preview. Changes no system network settings.

One bottleneck link (rate, FIFO buffer sized in ms, tail drop, optional random loss) carries:
- real SRT/UDP from a local publisher (ffmpeg) to MediaMTX, both on this host;
- simulated proxy uploads: Reno-style TCP flows fed one segment at a time (K1 PUTs one 6 s
  MPEG-TS segment per part), or with an endless backlog (catch-up), optionally paced (R10 maxKbps);
- an optional constant-rate UDP flow standing in for a second camera's preview.
Return traffic (MediaMTX -> publisher, TCP ACKs) gets the one-way delay only (downlink is not
the bottleneck). Writes one JSON line per second to --out.

  python3 scripts/uplink_shaper.py --listen 127.0.0.1:19890 --server 127.0.0.1:18890 \
      --rate-kbps 4000 --buffer-ms 500 --proxies 1 --proxy-mode backlog --duration 100 --out x.jsonl
"""
import argparse
import collections
import heapq
import itertools
import json
import random
import select
import socket
import time

UDP_IP_OVERHEAD = 28
TCP_WIRE, TCP_PAYLOAD = 1500, 1448
CBR_PACKET = 1316 + 16 + UDP_IP_OVERHEAD


def addr(text):
    host, _, port = text.rpartition(":")
    return host, int(port)


class Link:
    """Rate-limited FIFO with a byte cap; deliver(pkt, t) runs one-way-delay after transmission."""

    def __init__(self, sim, rate_kbps, buffer_ms, owd_s, loss):
        self.sim, self.bps, self.owd, self.loss = sim, rate_kbps * 1000, owd_s, loss
        self.cap = self.bps * buffer_ms / 8000
        self.queue, self.bytes, self.free_at = collections.deque(), 0, 0.0

    def offer(self, now, flow, size, deliver, on_drop=None):
        st = self.sim.stats[flow]
        st["offered"] += 1
        if self.bytes + size > self.cap:
            st["tailDrops"] += 1
        elif self.loss and random.random() < self.loss:
            st["randomDrops"] += 1
        else:
            self.queue.append((now, flow, size, deliver))
            self.bytes += size
            return True
        if on_drop:
            on_drop(now)
        return False

    def service(self, now):
        while self.queue and self.free_at <= now:
            enq, flow, size, deliver = self.queue.popleft()
            self.bytes -= size
            start = max(self.free_at, enq)
            self.free_at = start + size * 8 / self.bps
            st = self.sim.stats[flow]
            st["sentBytes"] += size
            st["sojournMs"].append((start - enq) * 1000)
            self.sim.at(self.free_at + self.owd, deliver)

    def next_time(self):
        return self.free_at if self.queue else None

    def queue_ms(self):
        return self.bytes * 8000 / self.bps


class Tcp:
    """Reno-ish: slow start, +1/cwnd per ACK, halve once per RTT on loss, slow start after idle."""

    def __init__(self, sim, name, pace_kbps):
        self.sim, self.name = sim, name
        self.cwnd, self.ssthresh, self.inflight = 10.0, float("inf"), 0
        self.backlog, self.endless = 0, False
        self.srtt, self.recover_until, self.idle_since = 2 * sim.owd + 0.01, 0.0, None
        self.pace_bps = pace_kbps * 1000
        self.tokens, self.tokens_t, self.wake_pending = TCP_WIRE * 2, 0.0, False

    def add(self, now, payload_bytes):
        if self.idle_since is not None and now - self.idle_since > max(0.2, 2 * self.srtt):
            self.cwnd = min(self.cwnd, 10.0)
        self.idle_since = None
        self.backlog += payload_bytes
        self.pump(now)

    def has_data(self):
        return self.endless or self.backlog > 0

    def pump(self, now):
        if self.pace_bps:
            self.tokens = min(TCP_WIRE * 2, self.tokens + (now - self.tokens_t) * self.pace_bps / 8)
            self.tokens_t = now
        while self.inflight < int(self.cwnd) and self.has_data():
            if self.pace_bps and self.tokens < TCP_WIRE:
                if not self.wake_pending:
                    self.wake_pending = True
                    self.sim.at(now + (TCP_WIRE - self.tokens) * 8 / self.pace_bps, self.woken)
                return
            if self.pace_bps:
                self.tokens -= TCP_WIRE
            if not self.endless:
                self.backlog -= TCP_PAYLOAD
            self.inflight += 1
            sent = now
            self.sim.link.offer(now, self.name, TCP_WIRE,
                                lambda t, s=sent: self.sim.at(t + self.sim.owd, lambda t2: self.ack(t2, s)),
                                lambda t: self.sim.at(t + self.srtt, self.lost))
        if not self.has_data() and self.inflight == 0 and self.idle_since is None:
            self.idle_since = now

    def woken(self, now):
        self.wake_pending = False
        self.pump(now)

    def ack(self, now, sent):
        self.inflight -= 1
        self.sim.stats[self.name]["goodputBytes"] += TCP_PAYLOAD
        self.srtt = 0.875 * self.srtt + 0.125 * (now - sent)
        self.cwnd += 1 if self.cwnd < self.ssthresh else 1 / self.cwnd
        self.pump(now)

    def lost(self, now):
        self.inflight -= 1
        if not self.endless:
            self.backlog += TCP_PAYLOAD
        if now >= self.recover_until:
            self.ssthresh = max(self.cwnd / 2, 2.0)
            self.cwnd = self.ssthresh
            self.recover_until = now + self.srtt
        self.pump(now)


class Sim:
    def __init__(self, a):
        self.a, self.owd = a, a.owd_ms / 1000
        self.events, self.seq = [], itertools.count()
        self.stats = collections.defaultdict(lambda: collections.Counter(sojournMs=[]))
        for flow in ("srt", "cbr", *(f"proxy{i}" for i in range(a.proxies))):
            self.stats[flow]["sojournMs"] = []
        self.link = Link(self, a.rate_kbps, a.buffer_ms, self.owd, a.loss)
        self.tcps = [Tcp(self, f"proxy{i}", a.pace_kbps) for i in range(a.proxies)]

    def at(self, t, fn):
        heapq.heappush(self.events, (t, next(self.seq), fn))

    def run(self):
        a = self.a
        client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client.bind(addr(a.listen))
        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        upstream.bind(("127.0.0.1", 0))
        server, peer = addr(a.server), None
        for s in (client, upstream):
            s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
            s.setblocking(False)

        t0 = time.monotonic()
        end = t0 + a.duration
        proxy_t0 = t0 + a.proxy_start_s
        for i, tcp in enumerate(self.tcps):
            if a.proxy_mode == "backlog":
                self.at(proxy_t0, lambda now, tcp=tcp: (setattr(tcp, "endless", True), tcp.add(now, 0)))
            else:
                seg_bytes = a.proxy_kbps * 1000 * a.segment_s / 8
                first = proxy_t0 + i * a.segment_s / max(1, a.proxies)

                def segment(now, due, tcp=tcp, seg_bytes=seg_bytes):
                    tcp.add(now, seg_bytes)
                    self.at(due + a.segment_s, lambda t, d=due + a.segment_s: segment(t, d))

                self.at(first, lambda t, d=first: segment(t, d))
        if a.cbr_kbps:
            gap = CBR_PACKET * 8 / (a.cbr_kbps * 1000)

            def cbr(now):
                self.link.offer(now, "cbr", CBR_PACKET, lambda t: None)
                self.at(now + gap, cbr)

            self.at(t0 + a.cbr_start_s, cbr)

        out = open(a.out, "w")
        next_stat = t0 + 1
        while True:
            now = time.monotonic()
            if now >= end:
                break
            nexts = [next_stat, end]
            if self.events:
                nexts.append(self.events[0][0])
            if (lt := self.link.next_time()) is not None:
                nexts.append(lt)
            readable, _, _ = select.select([client, upstream], [], [], max(0.0, min(nexts) - now))
            now = time.monotonic()
            for s in readable:
                while True:
                    try:
                        data, src = s.recvfrom(65536)
                    except BlockingIOError:
                        break
                    if s is client:
                        peer = src
                        self.link.offer(now, "srt", len(data) + UDP_IP_OVERHEAD,
                                        lambda t, d=data: upstream.sendto(d, server))
                    elif peer:
                        self.at(now + self.owd, lambda t, d=data, p=peer: client.sendto(d, p))
            while self.events and self.events[0][0] <= now:
                _, _, fn = heapq.heappop(self.events)
                fn(now)
            self.link.service(now)
            if now >= next_stat:
                out.write(json.dumps(self.snapshot(now - t0)) + "\n")
                out.flush()
                next_stat += 1
        out.close()

    def snapshot(self, t):
        row = {"t": round(t, 1), "queueMs": round(self.link.queue_ms(), 1), "flows": {}}
        for flow, st in self.stats.items():
            soj = sorted(st["sojournMs"])
            row["flows"][flow] = {
                "kbps": round(st["sentBytes"] * 8 / 1000, 1),
                "offered": st["offered"], "tailDrops": st["tailDrops"], "randomDrops": st["randomDrops"],
                "sojournP50Ms": round(soj[len(soj) // 2], 1) if soj else None,
                "sojournMaxMs": round(soj[-1], 1) if soj else None,
            }
            if st["goodputBytes"]:
                row["flows"][flow]["goodputKbps"] = round(st["goodputBytes"] * 8 / 1000, 1)
            self.stats[flow] = collections.Counter(sojournMs=[])
        for tcp in self.tcps:
            row["flows"].setdefault(tcp.name, {}).update(
                cwnd=round(tcp.cwnd, 1), backlogKB=None if tcp.endless else round(tcp.backlog / 1000))
        return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="127.0.0.1:19890", help="publisher sends SRT here")
    ap.add_argument("--server", default="127.0.0.1:18890", help="MediaMTX SRT address")
    ap.add_argument("--rate-kbps", type=float, default=4000, help="uplink rate")
    ap.add_argument("--buffer-ms", type=float, default=500, help="bottleneck buffer at the uplink rate")
    ap.add_argument("--owd-ms", type=float, default=15, help="one-way delay each direction")
    ap.add_argument("--loss", type=float, default=0.0, help="random uplink loss probability")
    ap.add_argument("--proxies", type=int, default=0, help="simulated proxy upload flows")
    ap.add_argument("--proxy-mode", choices=["segments", "backlog"], default="segments")
    ap.add_argument("--proxy-kbps", type=float, default=2470, help="proxy file rate (segments mode)")
    ap.add_argument("--segment-s", type=float, default=6)
    ap.add_argument("--pace-kbps", type=float, default=0, help="per-flow wire pacing, 0 = none")
    ap.add_argument("--proxy-start-s", type=float, default=15)
    ap.add_argument("--cbr-kbps", type=float, default=0, help="second camera preview stand-in")
    ap.add_argument("--cbr-start-s", type=float, default=0)
    ap.add_argument("--duration", type=float, default=100)
    ap.add_argument("--out", required=True)
    Sim(ap.parse_args()).run()


if __name__ == "__main__":
    main()
