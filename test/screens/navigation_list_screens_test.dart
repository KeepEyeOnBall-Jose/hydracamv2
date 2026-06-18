import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/screens/courts_screen.dart";
import "package:hydracam/screens/sports_centers_screen.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/widgets/hydracam_surface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    M2MAuthService.overrideTokenForTests("test-token");
  });

  tearDown(() {
    HydraCamApiService.resetHttpClient();
    M2MAuthService.clearTokenOverrideForTests();
  });

  testWidgets("sports center and court lists use operational cards and badges",
      (tester) async {
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        if (request.url.path.endsWith("/sportscenters")) {
          return http.Response(
            jsonEncode([
              {
                "guid": "sports-center-guid",
                "name": "Keepeyeonball Club",
                "city": "Berlin",
                "numberOfCourts": 3,
              },
            ]),
            200,
          );
        }

        if (request.url.path.endsWith("/courts")) {
          expect(
            request.url.queryParameters["sportsCenterGuid"],
            "sports-center-guid",
          );
          return http.Response(
            jsonEncode([
              {
                "guid": "court-guid",
                "name": "Court A",
                "location": "Main hall",
              },
            ]),
            200,
          );
        }

        fail("Unexpected request: ${request.url}");
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SportsCentersScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HydraCamSurface), findsOneWidget);
    expect(find.text("Keepeyeonball Club"), findsOneWidget);
    expect(find.text("Berlin"), findsOneWidget);
    expect(find.text("Courts: 3"), findsOneWidget);
    expect(find.byIcon(Icons.location_city_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sports_tennis_outlined), findsOneWidget);

    await tester.tap(find.text("Keepeyeonball Club"));
    await tester.pumpAndSettle();

    expect(find.text("Court A"), findsOneWidget);
    expect(find.text("Main hall"), findsOneWidget);
    expect(find.text("Sessions"), findsOneWidget);
    expect(find.byIcon(Icons.sports_tennis_outlined), findsOneWidget);
    expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("court list fits compact width without overflow", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(320, 420));

    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        expect(request.url.path.endsWith("/courts"), isTrue);
        return http.Response(
          jsonEncode([
            {
              "guid": "court-guid",
              "name": "A very long championship glass court name",
              "location": "Main hall near camera bridge",
            },
          ]),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CourtsScreen(sportsCenterGuid: "sports-center-guid"),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HydraCamSurface), findsOneWidget);
    expect(find.textContaining("championship"), findsOneWidget);
    expect(find.text("Sessions"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
