# Channel discovery via Discord REST

Use only when the target channel is unknown — the MCP exposes no lookup tools.
The bot token lives in the shell environment (`$DISCORD_TOKEN`, exported from
`~/.zshenv`). Authenticate with the `Bot` scheme; never paste the token into
command output you would show.

## List servers the bot is in

```sh
curl -s -H "Authorization: Bot $DISCORD_TOKEN" \
  https://discord.com/api/v10/users/@me/guilds
```

## List text channels of a guild

```sh
curl -s -H "Authorization: Bot $DISCORD_TOKEN" \
  https://discord.com/api/v10/guilds/<GUILD_ID>/channels
```

Pick `type: 0` (text) or `type: 5` (announcement) channels; map `name → id`.

## Find a member by name

```sh
curl -s -H "Authorization: Bot $DISCORD_TOKEN" \
  "https://discord.com/api/v10/guilds/<GUILD_ID>/members/search?query=<NAME>&limit=5"
```

Filter out entries where `user.bot` is true.

## Open a DM channel with a member

```sh
curl -s -X POST -H "Authorization: Bot $DISCORD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recipient_id":"<USER_ID>"}' \
  https://discord.com/api/v10/users/@me/channels
```

Works only across a shared guild; the bot dms users, never itself. The `id`
of the response is the channel to pass to `discord_send`.
