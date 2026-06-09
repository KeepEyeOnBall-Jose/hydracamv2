import "package:flutter/material.dart";
import "package:photo_manager/photo_manager.dart";
import "../models/capture_session.dart";
import "../services/gallery_session_matcher.dart";

/// A screen to display and select media files.
class MediaSelectionScreen extends StatefulWidget {
  final List<AssetEntity> mediaList;
  final List<CaptureSession> candidateSessions;
  final Duration candidateMargin;

  const MediaSelectionScreen({
    super.key,
    required this.mediaList,
    this.candidateSessions = const [],
    this.candidateMargin = GallerySessionMatcher.defaultMargin,
  });

  @override
  MediaSelectionScreenState createState() => MediaSelectionScreenState();
}

class MediaSelectionScreenState extends State<MediaSelectionScreen> {
  Set<AssetEntity> selectedMedia = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Media"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, selectedMedia.toList());
            },
            child: const Text(
              "Done",
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
      body: GridView.builder(
        itemCount: widget.mediaList.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        itemBuilder: (context, index) {
          final AssetEntity asset = widget.mediaList[index];
          final GallerySessionCandidate? candidate = _bestCandidateFor(asset);
          final String? candidateLabel = candidate?.session.preferredIdentifier;

          return GestureDetector(
            onTap: () {
              setState(() {
                if (selectedMedia.contains(asset)) {
                  selectedMedia.remove(asset);
                } else {
                  selectedMedia.add(asset);
                }
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Widget>(
                  future: _buildThumbnail(asset),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData) {
                      return snapshot.data!;
                    }

                    return Container(
                      color: Colors.grey[300],
                    );
                  },
                ),
                if (candidate != null)
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      color: Colors.black54,
                      child: Text(
                        "Candidate: $candidateLabel",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                if (selectedMedia.contains(asset))
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  GallerySessionCandidate? _bestCandidateFor(AssetEntity asset) {
    if (asset.type != AssetType.video || widget.candidateSessions.isEmpty) {
      return null;
    }

    final candidates = const GallerySessionMatcher().findVideoRangeCandidates(
      videoStart: asset.createDateTime,
      videoEnd: asset.createDateTime.add(asset.videoDuration),
      sessions: widget.candidateSessions,
      margin: widget.candidateMargin,
    );
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  Future<Widget> _buildThumbnail(AssetEntity asset) async {
    final thumbnailData =
        await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
    if (thumbnailData != null) {
      return Image.memory(
        thumbnailData,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      return Container(color: Colors.grey);
    }
  }
}
