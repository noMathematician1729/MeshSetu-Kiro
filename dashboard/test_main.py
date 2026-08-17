import unittest

from fastapi.testclient import TestClient

from main import app, latest


class DashboardTest(unittest.TestCase):
    def setUp(self):
        latest.clear()
        self.client = TestClient(app)

    def test_auth_and_partial_event_updates(self):
        self.assertEqual(
            self.client.post(
                "/api/events", json={"event_id": "e1"}
            ).status_code,
            401,
        )
        headers = {"x-meshsetu-demo-key": "change-me"}
        self.assertEqual(
            self.client.post(
                "/api/events",
                headers=headers,
                json={
                    "event_id": "e1",
                    "priority": "p0Critical",
                    "incident_type": "medical",
                    "transcript": "help",
                    "latitude": 19.076,
                    "longitude": 72.8777,
                    "accuracy_m": 8.5,
                    "location_captured_at_ms": 42,
                },
            ).status_code,
            200,
        )
        self.assertEqual(
            self.client.post(
                "/api/events",
                headers=headers,
                json={
                    "event_id": "e1",
                    "voice_clip_id": "clip-1",
                    "audio_state": "complete",
                },
            ).status_code,
            200,
        )
        event = self.client.get("/api/events").json()[0]
        self.assertEqual(event["transcript"], "help")
        self.assertEqual(event["latitude"], 19.076)
        self.assertEqual(event["longitude"], 72.8777)
        self.assertEqual(event["accuracy_m"], 8.5)
        self.assertEqual(event["location_captured_at_ms"], 42)
        self.assertEqual(event["audio_state"], "complete")


if __name__ == "__main__":
    unittest.main()
