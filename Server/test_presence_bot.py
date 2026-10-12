"""Bot-cache visibility tests; no real Discord requests or credentials."""
import unittest
from types import SimpleNamespace as Item
import discord
from presence_bot import visible_games


def member(status="online", name="Great Game", kind=discord.ActivityType.playing):
    return Item(status=status, activities=[] if name is None else [Item(type=kind, name=name)])


class Guild:
    unavailable = False
    def __init__(self, members):
        self.members = members
    def get_member(self, user):
        return self.members.get(user)


class BotGameTests(unittest.TestCase):
    def test_custom_status_text_emoji_and_privacy_removal(self):
        shared = Guild({100: member(), 200: member()})
        client = Item(is_ready=lambda: True, guilds=[shared])
        custom = discord.CustomActivity(name="Custom Status", state="  Making\n something nice  ", emoji="☀️")
        shared.members[200].activities.append(custom)
        result = visible_games(client, "100", ["200"])
        self.assertEqual(result["customStatuses"], [dict(discordID="200", text="☀️ Making something nice")])
        self.assertEqual(result["games"][0]["name"], "Great Game")
        custom.state = "x" * 400
        self.assertEqual(len(visible_games(client, "100", ["200"])["customStatuses"][0]["text"]), 280)
        shared.members[200].activities = [discord.CustomActivity(name="Custom Status", state=None, emoji="🎮")]
        self.assertEqual(visible_games(client, "100", ["200"])["customStatuses"][0]["text"], "🎮")
        # Discord's profile privacy can omit type 4 while retaining a game.
        shared.members[200] = member()
        self.assertEqual(visible_games(client, "100", ["200"])["customStatuses"], [])
        shared.members[200].activities.append(custom)
        shared.members[200].status = "offline"
        self.assertEqual(visible_games(client, "100", ["200"])["customStatuses"], [])
        shared.members[200].status = "online"
        self.assertEqual(visible_games(client, "999", ["200"])["customStatuses"], [])

    def test_only_shared_guild_members_visible_playing_activity_is_returned(self):
        shared = Guild({100: member(), 200: member(), 300: member(kind=discord.ActivityType.listening), 400: member(status="offline")})
        hidden = Guild({500: member(name="Private Game")})
        client = Item(is_ready=lambda: True, guilds=[shared, hidden])
        result = visible_games(client, "100", ["200", "300", "400", "500"])
        self.assertEqual(result["coveredDiscordIDs"], ["200", "300", "400"])
        self.assertEqual(result["games"], [dict(discordID="200", name="Great Game")])
        shared.members.pop(100)
        self.assertEqual(visible_games(client, "100", ["200"])["games"], [])

    def test_stop_hiding_disconnect_and_unavailable_guild_clear_current_games(self):
        shared = Guild({100: member(), 200: member()})
        client = Item(is_ready=lambda: True, guilds=[shared])
        self.assertEqual(len(visible_games(client, "100", ["200"])["games"]), 1)
        shared.members[200].activities = []
        self.assertEqual(visible_games(client, "100", ["200"])["games"], [])
        shared.members[200] = member()
        shared.unavailable = True
        self.assertEqual(visible_games(client, "100", ["200"])["coveredDiscordIDs"], [])
        client.is_ready = lambda: False
        self.assertEqual(visible_games(client, "100", ["200"]), dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[]))


if __name__ == "__main__":
    unittest.main()
