"""Optional Discord presence adapter; reads only guild-visible presence data."""
import threading
import asyncio
from concurrent.futures import TimeoutError
import discord


def visible_games(client, viewer, targets):
    """Discord-visible games and custom statuses in a guild shared with the viewer.

    Called on the Discord event loop. Never fetches arbitrary users or retains
    the requested friend list; offline, hidden and unavailable members have no game.
    """
    if not client.is_ready():
        return dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[])
    covered, games, statuses = set(), {}, {}
    for guild in list(client.guilds):
        if guild.unavailable or guild.get_member(int(viewer)) is None:
            continue
        for target in targets:
            member = guild.get_member(int(target))
            if member is None:
                continue
            covered.add(target)
            if str(member.status) not in ("online", "idle", "dnd"):
                continue
            game = next((str(a.name)[:100] for a in member.activities
                         if a.type == discord.ActivityType.playing and a.name), None)
            if game:
                games[target] = dict(discordID=target, name=game)
            # Discord omits type 4 when profile privacy denies this guild access.
            # Never infer it from another activity's name, details, or state.
            custom = next((a for a in member.activities if a.type == discord.ActivityType.custom), None)
            if custom is not None:
                value = " ".join((getattr(custom, "state", None) or "").split())
                emoji = getattr(custom, "emoji", None)
                if emoji and emoji.name:
                    symbol = ":" + emoji.name + ":" if emoji.id else emoji.name
                    value = symbol + (" " + value if value else "")
                if value:
                    statuses[target] = dict(discordID=target, text=value[:280])
    return dict(state="ready", coveredDiscordIDs=sorted(covered), games=list(games.values()), customStatuses=list(statuses.values()))


def start_bot(service, token):
    intents = discord.Intents.none()
    intents.guilds = intents.members = intents.presences = True
    client = discord.Client(intents=intents)

    async def snapshot_games(viewer, targets):
        return visible_games(client, viewer, targets)

    def read_games(viewer, targets):
        if not client.is_ready() or client.is_closed():
            return dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[])
        future = asyncio.run_coroutine_threadsafe(snapshot_games(viewer, targets), client.loop)
        try:
            return future.result(timeout=3)
        except TimeoutError:
            future.cancel()
            return dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[])

    service.discord_games = read_games

    def game(member):
        return next((str(a.name)[:100] for a in member.activities if a.type == discord.ActivityType.playing and a.name), None)

    def record(guild):
        if guild.unavailable:
            return
        with service.lock:
            users = [int(row[0]) for row in service.db.execute("SELECT discord_id FROM accounts WHERE share_presence=1 OR share_activity=1")]
        for user in users:
            member = guild.get_member(user)
            if member:
                service.set_presence(guild.id, member.id, str(member.status), game(member))

    @client.event
    async def on_ready():
        with service.lock:
            service.bot_connected = True
            service.clear_presence()
            for guild in client.guilds:
                record(guild)
        print("Discord presence bot connected.", flush=True)

    @client.event
    async def on_resumed():
        await on_ready()

    @client.event
    async def on_disconnect():
        with service.lock:
            service.bot_connected = False
            service.clear_presence()

    @client.event
    async def on_presence_update(before, after):
        service.set_presence(after.guild.id, after.id, str(after.status), game(after))

    @client.event
    async def on_member_remove(member):
        service.clear_presence(guild=member.guild.id, user=member.id)

    @client.event
    async def on_guild_remove(guild):
        service.clear_presence(guild=guild.id)

    @client.event
    async def on_guild_unavailable(guild):
        service.clear_presence(guild=guild.id)

    @client.event
    async def on_guild_available(guild):
        record(guild)

    # Newly opted-in users need a snapshot even if Discord hasn't sent a change.
    from discord.ext import tasks

    @tasks.loop(seconds=30)
    async def refresh():
        if client.is_ready():
            for guild in client.guilds:
                record(guild)

    @client.event
    async def setup_hook():
        refresh.start()

    def run():
        try:
            client.run(token, log_handler=None)
        except Exception:
            with service.lock:
                service.bot_connected = False
                service.clear_presence()
            print("Discord presence bot stopped. Check credentials and privileged intents.", flush=True)

    threading.Thread(target=run, daemon=True, name="discord-presence").start()
