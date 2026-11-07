---
name: Discord Msg
description: Send a Discord message or DM as hugoplanet-bot (hugo's bot) via the discord MCP, always carrying the model watermark. Use whenever hugo asks to send, reply, notify, or DM on Discord.
---

# Send a Discord message on behalf of hugo

## Known IDs

No discovery tools exist in the MCP. Cache these; they are the only lookup-free
source of truth:

| What                              | Value                 |
| --------------------------------- | --------------------- |
| hugo's user ID                    | `1460659958742781962` |
| DM channel (bot ↔ hugo)           | `1568428556944412776` |
| bot user ID (hugoplanet-bot#2526) | `1568424460518694962` |
| guild `exit`                      | `1552034244711157830` |
| guild `vvh-ab`                    | `1557121683410657391` |
| guild `emil-hugo-ab`              | `1557123098539589672` |

## Steps

1. **Login**. Skip if a login already succeeded this session.
   - Call `tools.discord.discord_login({})`.
   - If it reports the token missing: read it from the shell (`echo $DISCORD_TOKEN`,
     the value lives in `~/.zshenv`), then call login with `{ token: "<token>" }`.
     The token appears in the call only; never write it into a file or a message body.
   - Done when the reply names `hugoplanet-bot`.

2. **Pick the channel**. Default target is the DM channel with hugo
   (`1568428556944412776`) unless hugo names another channel or member.
   An unknown channel is a not-found branch: follow `references/discovery.md`
   to resolve it, then continue here.

3. **Send** through `tools.discord.discord_send({ channelId, message })`,
   never raw curl. Long, multi-paragraph bodies are fine.

4. **Watermark**. Every message carries a stylized signature after the body,
   naming the model that generated the message and stating it is sent on
   behalf of hugo. Base template — substitute the active model's name, then
   own the styling:

   ```
   ─── ✦ *<model> · for hugo · opencode discord-mcp* ✦ ───
   ```

   Example with the shape filled in:

   ```
   ─── ✦ *delivered by GLM-5.3-Flash · on behalf of hugo · opencode discord-mcp* ✦ ───
   ```

   Rewrite the flourish (glyphs, wording) freely; keep both facts present:
   which model, whose behalf.

Done when `discord_send` reports success and the sent body ends with the
watermark naming the current model.
