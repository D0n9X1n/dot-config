#!/usr/bin/env python3
"""WakaTime MCP Server - High-signal coding analytics tools."""

import os
from datetime import date, timedelta
from typing import Literal

from fastmcp import FastMCP

from wakatime_client import (
    WakaTimeClient,
    WakaTimeError,
    WakaTimeAuthError,
    WakaTimeNotReadyError,
    WakaTimeRateLimitError,
)

mcp = FastMCP("WakaTime")

# Lazy-initialized client
_client: WakaTimeClient | None = None


def get_client() -> WakaTimeClient:
    """Get or create the WakaTime client."""
    global _client
    if _client is None:
        _client = WakaTimeClient()
    return _client


def format_error(e: Exception) -> dict:
    """Format an exception as a user-friendly error response."""
    if isinstance(e, WakaTimeAuthError):
        return {
            "error": "Authentication failed",
            "message": str(e),
            "help": "Set WAKATIME_API_KEY environment variable with your API key from https://wakatime.com/settings/api-key",
        }
    elif isinstance(e, WakaTimeRateLimitError):
        return {
            "error": "Rate limit exceeded",
            "message": str(e),
            "help": "WakaTime allows ~10 requests/second. Wait a moment and try again.",
        }
    elif isinstance(e, WakaTimeNotReadyError):
        return {
            "error": "Stats computing",
            "message": str(e),
            "help": "WakaTime is still calculating your stats. Try again in a few seconds.",
        }
    else:
        return {
            "error": "API error",
            "message": str(e),
        }


StatsRange = Literal[
    "last_7_days", "last_30_days", "last_6_months", "last_year", "all_time"
]


@mcp.tool(
    description="Get your coding statistics for a time range. Returns languages, projects, editors, total time, daily average, and best coding day. Use this to understand coding patterns and productivity over time."
)
async def get_coding_stats(
    range: StatsRange = "last_7_days",
) -> dict:
    """
    Get coding statistics for a specified time range.

    Args:
        range: Time range - one of "last_7_days", "last_30_days", "last_6_months", "last_year", "all_time"

    Returns:
        Coding stats including languages, projects, editors, total time, daily average, best day
    """
    try:
        client = get_client()
        stats = await client.get_stats(range)

        # Extract and format the most useful data
        result = {
            "range": stats.get("human_readable_range", range),
            "total_time": stats.get("human_readable_total", "0 mins"),
            "total_seconds": stats.get("total_seconds", 0),
            "daily_average": stats.get("human_readable_daily_average", "0 mins"),
            "days_including_holidays": stats.get("days_including_holidays", 0),
            "days_minus_holidays": stats.get("days_minus_holidays", 0),
        }

        # Best day
        best_day = stats.get("best_day")
        if best_day:
            result["best_day"] = {
                "date": best_day.get("date"),
                "time": best_day.get("text", ""),
                "total_seconds": best_day.get("total_seconds", 0),
            }

        # Languages (top 10)
        languages = stats.get("languages", [])
        result["languages"] = [
            {
                "name": lang.get("name"),
                "time": lang.get("text", ""),
                "percent": round(lang.get("percent", 0), 1),
                "total_seconds": lang.get("total_seconds", 0),
            }
            for lang in languages[:10]
        ]

        # Projects (top 10)
        projects = stats.get("projects", [])
        result["projects"] = [
            {
                "name": proj.get("name"),
                "time": proj.get("text", ""),
                "percent": round(proj.get("percent", 0), 1),
                "total_seconds": proj.get("total_seconds", 0),
            }
            for proj in projects[:10]
        ]

        # Editors (top 5)
        editors = stats.get("editors", [])
        result["editors"] = [
            {
                "name": ed.get("name"),
                "time": ed.get("text", ""),
                "percent": round(ed.get("percent", 0), 1),
            }
            for ed in editors[:5]
        ]

        # Operating Systems
        operating_systems = stats.get("operating_systems", [])
        result["operating_systems"] = [
            {
                "name": os_item.get("name"),
                "time": os_item.get("text", ""),
                "percent": round(os_item.get("percent", 0), 1),
            }
            for os_item in operating_systems[:5]
        ]

        # Categories (coding, debugging, etc.)
        categories = stats.get("categories", [])
        result["categories"] = [
            {
                "name": cat.get("name"),
                "time": cat.get("text", ""),
                "percent": round(cat.get("percent", 0), 1),
            }
            for cat in categories[:5]
        ]

        return result

    except Exception as e:
        return format_error(e)


def parse_date(date_str: str | None) -> date | None:
    """Parse a date string in YYYY-MM-DD format."""
    if not date_str:
        return None
    try:
        return date.fromisoformat(date_str)
    except ValueError:
        return None


@mcp.tool(
    description="Get a summary of coding activity for a date or date range. Shows time distribution across projects, languages, editors. Defaults to last ~24 hours (yesterday + today). Use for daily standups, weekly reviews, or analyzing specific time periods."
)
async def get_summary(
    start_date: str | None = None,
    end_date: str | None = None,
    project: str | None = None,
) -> dict:
    """
    Get coding summary for a date or date range.

    Args:
        start_date: Start date in YYYY-MM-DD format (defaults to yesterday for ~24hr view)
        end_date: End date in YYYY-MM-DD format (defaults to today)
        project: Optional project name to filter by

    Returns:
        Coding activity including projects, languages, editors, and total time
    """
    try:
        client = get_client()

        # Parse dates - default to yesterday through today (~24-48 hours of activity)
        today = date.today()
        yesterday = today - timedelta(days=1)

        start = parse_date(start_date) or yesterday
        end = parse_date(end_date) or today

        # Validate date range
        if end < start:
            return {
                "error": "Invalid date range",
                "message": "end_date cannot be before start_date",
            }

        response = await client.get_summaries(start=start, end=end, project=project)

        summaries = response.get("data", [])
        if not summaries:
            return {
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
                "total_time": "0 mins",
                "total_seconds": 0,
                "message": "No coding activity recorded for this period.",
            }

        # For single day, return that day's summary
        # For date range, aggregate across all days
        is_range = start != end

        if is_range:
            # Aggregate totals across all days
            total_seconds = 0
            project_totals: dict[str, float] = {}
            language_totals: dict[str, float] = {}
            editor_totals: dict[str, float] = {}
            category_totals: dict[str, float] = {}

            for day_summary in summaries:
                grand_total = day_summary.get("grand_total", {})
                total_seconds += grand_total.get("total_seconds", 0)

                for proj in day_summary.get("projects", []):
                    name = proj.get("name", "Unknown")
                    project_totals[name] = project_totals.get(name, 0) + proj.get(
                        "total_seconds", 0
                    )

                for lang in day_summary.get("languages", []):
                    name = lang.get("name", "Unknown")
                    language_totals[name] = language_totals.get(name, 0) + lang.get(
                        "total_seconds", 0
                    )

                for ed in day_summary.get("editors", []):
                    name = ed.get("name", "Unknown")
                    editor_totals[name] = editor_totals.get(name, 0) + ed.get(
                        "total_seconds", 0
                    )

                for cat in day_summary.get("categories", []):
                    name = cat.get("name", "Unknown")
                    category_totals[name] = category_totals.get(name, 0) + cat.get(
                        "total_seconds", 0
                    )

            # Calculate percentages and format
            def format_breakdown(
                totals: dict[str, float], limit: int = 10
            ) -> list[dict]:
                sorted_items = sorted(totals.items(), key=lambda x: x[1], reverse=True)[
                    :limit
                ]
                return [
                    {
                        "name": name,
                        "time": client.format_seconds(secs),
                        "percent": round((secs / total_seconds) * 100, 1)
                        if total_seconds > 0
                        else 0,
                        "total_seconds": secs,
                    }
                    for name, secs in sorted_items
                ]

            num_days = (end - start).days + 1
            result = {
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
                "num_days": num_days,
                "total_time": client.format_seconds(total_seconds),
                "total_seconds": total_seconds,
                "daily_average": client.format_seconds(total_seconds / num_days)
                if num_days > 0
                else "0 mins",
                "projects": format_breakdown(project_totals),
                "languages": format_breakdown(language_totals),
                "editors": format_breakdown(editor_totals, limit=5),
                "categories": format_breakdown(category_totals, limit=5),
            }
        else:
            # Single day - use the summary directly
            summary = summaries[0]
            grand_total = summary.get("grand_total", {})

            result = {
                "date": summary.get("range", {}).get("date", start.isoformat()),
                "total_time": grand_total.get("text", "0 mins"),
                "total_seconds": grand_total.get("total_seconds", 0),
            }

            # Projects
            projects = summary.get("projects", [])
            result["projects"] = [
                {
                    "name": proj.get("name"),
                    "time": proj.get("text", ""),
                    "percent": round(proj.get("percent", 0), 1),
                    "total_seconds": proj.get("total_seconds", 0),
                }
                for proj in projects[:10]
            ]

            # Languages
            languages = summary.get("languages", [])
            result["languages"] = [
                {
                    "name": lang.get("name"),
                    "time": lang.get("text", ""),
                    "percent": round(lang.get("percent", 0), 1),
                }
                for lang in languages[:10]
            ]

            # Editors
            editors = summary.get("editors", [])
            result["editors"] = [
                {
                    "name": ed.get("name"),
                    "time": ed.get("text", ""),
                    "percent": round(ed.get("percent", 0), 1),
                }
                for ed in editors[:5]
            ]

            # Categories
            categories = summary.get("categories", [])
            result["categories"] = [
                {
                    "name": cat.get("name"),
                    "time": cat.get("text", ""),
                    "percent": round(cat.get("percent", 0), 1),
                }
                for cat in categories[:5]
            ]

        if project:
            result["project_filter"] = project

        return result

    except Exception as e:
        return format_error(e)


@mcp.tool(
    description="Get your total coding time since you created your WakaTime account. Optionally filter by a specific project. Great for seeing your all-time investment in coding."
)
async def get_all_time(project: str | None = None) -> dict:
    """
    Get total coding time since account creation.

    Args:
        project: Optional project name to filter by

    Returns:
        Total time, daily average, and date range
    """
    try:
        client = get_client()
        data = await client.get_all_time_since_today(project=project)

        result = {
            "total_time": data.get("text", "0 mins"),
            "total_seconds": data.get("total_seconds", 0),
            "daily_average_seconds": data.get("daily_average", 0),
            "is_up_to_date": data.get("is_up_to_date", False),
        }

        # Add date range info
        range_info = data.get("range", {})
        if range_info:
            result["range"] = {
                "start": range_info.get("start_text", ""),
                "end": range_info.get("end_text", ""),
                "start_date": range_info.get("start_date"),
                "end_date": range_info.get("end_date"),
            }

        if project:
            result["project"] = project

        # Format daily average
        daily_avg = data.get("daily_average", 0)
        result["daily_average"] = client.format_seconds(daily_avg)

        return result

    except Exception as e:
        return format_error(e)


@mcp.tool(
    description="Get your current coding status - what you're working on right now and today's total time. Shows the same info as the WakaTime status bar in your editor."
)
async def get_status_bar() -> dict:
    """
    Get current status bar information.

    Returns:
        Today's grand total time and caching status
    """
    try:
        client = get_client()
        data = await client.get_status_bar()

        grand_total = data.get("grand_total", {})
        categories = data.get("categories", [])

        result = {
            "today_total": grand_total.get("text", "0 mins"),
            "today_total_seconds": grand_total.get("total_seconds", 0),
            "is_cached": data.get("cached_at") is not None,
        }

        # Add category breakdown if available
        if categories:
            result["categories"] = [
                {
                    "name": cat.get("name"),
                    "time": cat.get("text", ""),
                    "percent": round(cat.get("percent", 0), 1),
                }
                for cat in categories[:5]
            ]

        return result

    except Exception as e:
        return format_error(e)


@mcp.tool(
    description="List your WakaTime projects. Optionally search by name. Returns project names with their last activity timestamps."
)
async def list_projects(query: str | None = None) -> dict:
    """
    List tracked projects.

    Args:
        query: Optional search query to filter projects

    Returns:
        List of projects with metadata
    """
    try:
        client = get_client()
        projects = await client.get_projects(query=query)

        result = {
            "total_count": len(projects),
            "projects": [
                {
                    "name": proj.get("name"),
                    "id": proj.get("id"),
                    "last_heartbeat_at": proj.get("last_heartbeat_at"),
                    "created_at": proj.get("created_at"),
                    "has_public_url": proj.get("has_public_url", False),
                }
                for proj in projects[:50]  # Limit to 50 projects
            ],
        }

        if query:
            result["query"] = query

        return result

    except Exception as e:
        return format_error(e)


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "http":
        port = int(os.environ.get("PORT", 8000))
        host = "0.0.0.0"
        print(f"Starting WakaTime MCP server on {host}:{port}")
        mcp.run(transport="http", host=host, port=port, path="/mcp")
    else:
        mcp.run(transport="stdio")
