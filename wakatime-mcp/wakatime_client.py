"""WakaTime API client with authentication and error handling."""

import base64
import os
from datetime import date, datetime
from typing import Any

import httpx


class WakaTimeError(Exception):
    """Base exception for WakaTime API errors."""

    pass


class WakaTimeAuthError(WakaTimeError):
    """Authentication failed."""

    pass


class WakaTimeRateLimitError(WakaTimeError):
    """Rate limit exceeded."""

    pass


class WakaTimeNotReadyError(WakaTimeError):
    """Stats are still being computed (202 response)."""

    pass


class WakaTimeClient:
    """Client for interacting with the WakaTime API."""

    def __init__(
        self,
        api_key: str | None = None,
        base_url: str = "https://api.wakatime.com/api/v1",
        timeout: float = 30.0,
    ):
        self.base_url = base_url
        self.timeout = timeout

        if api_key is None:
            api_key = os.environ.get("WAKATIME_API_KEY")
        if not api_key:
            raise WakaTimeAuthError(
                "WAKATIME_API_KEY environment variable not set. "
                "Get your API key from https://wakatime.com/settings/api-key"
            )
        self.api_key: str = api_key

    def _get_auth_header(self) -> dict[str, str]:
        """Get the Authorization header with base64 encoded API key."""
        encoded = base64.b64encode(self.api_key.encode()).decode()
        return {"Authorization": f"Basic {encoded}"}

    async def _request(
        self, method: str, endpoint: str, params: dict | None = None
    ) -> dict[str, Any]:
        """Make an authenticated request to the WakaTime API."""
        url = f"{self.base_url}{endpoint}"
        headers = self._get_auth_header()

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.request(method, url, headers=headers, params=params)

            if response.status_code == 401:
                raise WakaTimeAuthError("Invalid API key")
            elif response.status_code == 202:
                # Stats are being computed, not ready yet
                data = response.json()
                percent = data.get("data", {}).get("percent_calculated", 0)
                raise WakaTimeNotReadyError(
                    f"Stats are still being computed ({percent}% complete). Try again in a few seconds."
                )
            elif response.status_code == 429:
                raise WakaTimeRateLimitError(
                    "Rate limit exceeded. WakaTime allows ~10 requests/second. "
                    "Please wait a moment before trying again."
                )
            elif response.status_code >= 400:
                error_msg = response.json().get("error", response.text)
                raise WakaTimeError(f"API error ({response.status_code}): {error_msg}")

            return response.json()

    async def get(self, endpoint: str, params: dict | None = None) -> dict[str, Any]:
        """Make a GET request to the WakaTime API."""
        return await self._request("GET", endpoint, params)

    # -------------------------------------------------------------------------
    # Helper methods for formatting
    # -------------------------------------------------------------------------

    @staticmethod
    def format_seconds(seconds: float | int) -> str:
        """Convert seconds to human-readable format like '5 hrs 30 mins'."""
        if seconds < 60:
            return f"{int(seconds)} secs"

        minutes = int(seconds // 60)
        if minutes < 60:
            return f"{minutes} mins"

        hours = minutes // 60
        remaining_mins = minutes % 60

        if hours < 24:
            if remaining_mins == 0:
                return f"{hours} hrs"
            return f"{hours} hrs {remaining_mins} mins"

        days = hours // 24
        remaining_hours = hours % 24
        if remaining_hours == 0:
            return f"{days} days"
        return f"{days} days {remaining_hours} hrs"

    @staticmethod
    def get_date_string(d: date | None = None) -> str:
        """Get a date string in YYYY-MM-DD format."""
        if d is None:
            d = date.today()
        return d.strftime("%Y-%m-%d")

    # -------------------------------------------------------------------------
    # API Methods
    # -------------------------------------------------------------------------

    async def get_current_user(self) -> dict[str, Any]:
        """Get the current authenticated user's information."""
        response = await self.get("/users/current")
        return response.get("data", {})

    async def get_stats(self, range: str = "last_7_days") -> dict[str, Any]:
        """
        Get coding stats for a time range.

        Args:
            range: One of "last_7_days", "last_30_days", "last_6_months",
                   "last_year", or "all_time"

        Returns:
            Stats including languages, projects, editors, total time, etc.
        """
        response = await self.get(f"/users/current/stats/{range}")
        return response.get("data", {})

    async def get_summaries(
        self,
        start: date | None = None,
        end: date | None = None,
        project: str | None = None,
    ) -> dict[str, Any]:
        """
        Get coding summaries for a date range.

        Args:
            start: Start date (defaults to today)
            end: End date (defaults to today)
            project: Optional project filter

        Returns:
            Daily summaries with projects, languages, editors, etc.
        """
        if start is None:
            start = date.today()
        if end is None:
            end = start

        params = {
            "start": self.get_date_string(start),
            "end": self.get_date_string(end),
        }
        if project:
            params["project"] = project

        response = await self.get("/users/current/summaries", params)
        return response

    async def get_all_time_since_today(
        self, project: str | None = None
    ) -> dict[str, Any]:
        """
        Get total coding time since account creation.

        Args:
            project: Optional project filter

        Returns:
            Total time, daily average, date range
        """
        params = {}
        if project:
            params["project"] = project

        response = await self.get("/users/current/all_time_since_today", params)
        return response.get("data", {})

    async def get_status_bar(self) -> dict[str, Any]:
        """
        Get today's status bar information (current session info).

        Returns:
            Today's grand total time and cached status
        """
        response = await self.get("/users/current/status_bar/today")
        return response.get("data", {})

    async def get_projects(self, query: str | None = None) -> list[dict[str, Any]]:
        """
        Get list of projects.

        Args:
            query: Optional search query

        Returns:
            List of projects with names and metadata
        """
        params = {}
        if query:
            params["q"] = query

        response = await self.get("/users/current/projects", params)
        return response.get("data", [])

    async def get_durations(
        self,
        date: date | None = None,
        project: str | None = None,
    ) -> dict[str, Any]:
        """
        Get coding durations for a specific day.

        Args:
            date: The date to get durations for (defaults to today)
            project: Optional project filter

        Returns:
            List of duration blocks with project, time, and duration
        """
        if date is None:
            date = datetime.now().date()

        params = {"date": self.get_date_string(date)}
        if project:
            params["project"] = project

        response = await self.get("/users/current/durations", params)
        return response

    async def get_goals(self) -> list[dict[str, Any]]:
        """
        Get user's coding goals.

        Returns:
            List of goals with progress and status
        """
        response = await self.get("/users/current/goals")
        return response.get("data", [])
