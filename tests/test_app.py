import unittest
from app import app

class AppTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_homepage_returns_success(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Cloud CI/CD Demo App", response.data)

    def test_health_endpoint(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        json_data = response.get_json()
        self.assertEqual(json_data.get("status"), "healthy")
        self.assertIn("version", json_data)

    def test_nonexistent_route_returns_404(self):
        response = self.client.get("/non-existent-endpoint")
        self.assertEqual(response.status_code, 404)

if __name__ == "__main__":
    unittest.main()
