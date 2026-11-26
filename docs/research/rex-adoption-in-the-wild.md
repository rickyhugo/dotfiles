# Rex adoption in the wild: what tmux users do when they move

Research date: 2026-11-26. Rex is in public beta since 2026-10-05
([announcement](https://www.superlogical.com/updates/public-testing-beginning)), so
all material is at most seven weeks old. Claims marked _(inferred)_ are my reading,
not a statement in a source. Counts from public configs are my own computation; the
method and its limits are in [section 6](#6-open-questions-and-evidence-gaps).

## 1. Answer in brief

- **Porting tmux keys is the majority path, and the vendor supports it.** About 55%
  of public Rex configs use a prefix-style key sequence, and 83% of the configs that
  mention tmux do ([section 3](#3-what-users-actually-do)). The app ships an
  onboarding flow that translates a `tmux.conf` into `prefix>key` binds (bundled
  guide, [section 2](#the-vendors-own-tmux-migration)). The docs have a
  ["Tmux Bindings" example](https://www.superlogical.com/rex/docs/customize/key-sequences#example-tmux-bindings).
- **What users port is keys, not machinery.** The typical tmux-migrant config is a
  prefix plus 30 to 60 binds to built-in actions. Median config size is about 90
  non-blank Lua lines. Nobody starts tmux from a Rex config (0 of 760).
- **Most users switch sessions with the built-in picker.** 59% of tmux-mentioning
  configs bind the built-in `session.switch` (default `cmd+k`). Only 15 to 20% build
  a project picker ("sessionizer").
- **A project picker has no built-in equivalent, but the common form is small.**
  Half of the project pickers use the native `rex.ui.pick` prompt (about 40 to 100
  lines), half use fzf in a floating layer (about 20 to 40 lines of shell). A Rex
  team member publishes a 761-line reference script,
  [almonk/rex-projects](https://github.com/almonk/rex-projects), built on
  `rex.ui.pick`.
- **Status line, tmux plugins and session-restore plugins are dropped, not
  rebuilt.** The bundled migration guide says they have "no counterpart" and tells
  the agent not to approximate them. About 2% of configs mention a status line.
- **Floating layers replace `display-popup`.** 40% of configs call
  `rex.session.new_layer`. About 90% of configs that launch lazygit use a floating
  layer, not a tab.
- **The setup in this repo is an outlier in size.** It is about 1,360 lines against
  a median near 90. Its session picker duplicates a built-in. Its project picker was
  written before `rex.ui.pick` reached the Preview channel (2026-11-19).
- **Evidence strength.** Official docs and the bundled guide: strong. Config
  corpus: strong on _what_ people bind, weak on _why_. First-hand narratives: thin
  (about ten Hacker News comments, two blog posts, one detailed migration log). No
  Reddit, X or Discord material was retrievable.

## 2. Rex's intended model

### Product position

- Superlogical calls Rex "the multiplexer for all work" and starts with a terminal
  multiplexer. The home page says: "If you're already familiar with terminal
  multiplexers, you'll feel right at home, but we're bringing a more modern touch."
  It lists native apps, session sharing, and fixing "scrollback, selection, and
  scrolling" as the differences
  ([superlogical.com](https://www.superlogical.com/)).
- The beta announcement positions Rex as "a drop-in replacement for whichever
  terminal you use today", with "persistent sessions, performant and responsive
  remote connections, program activity status"
  ([announcement](https://www.superlogical.com/updates/public-testing-beginning)).
- Rex is a terminal app plus a server. It is not a multiplexer that runs inside
  another terminal ([Session Restore](https://www.superlogical.com/rex/docs/features/session-restore),
  [first-hand test](https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/)).
- The source is not public. The `superlogical` GitHub organisation lists one public
  repo, a Sparkle fork ([github.com/superlogical](https://github.com/superlogical)).
  The app's update feed links to a private `superlogical/rex-app`
  ([appcast](https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml)).
  So there are no official example configs outside the docs.

### Objects

The [CLI page](https://www.superlogical.com/rex/docs/automate/cli#taxonomy) defines
four objects:

| Rex     | Definition in the docs                                                                                           |
| ------- | ---------------------------------------------------------------------------------------------------------------- |
| Session | "A group of related work, such as one project." The server keeps it running whether or not a client looks at it. |
| Window  | "A tab within a session." It holds a layout of blocks.                                                           |
| Block   | "One application in a window. Today that means a terminal."                                                      |
| Client  | A program connected to the server, such as the app.                                                              |

### Persistence

- A client restart restores all sessions as-is with full history, because the
  server holds the state.
- A server restart restores sessions, tabs and panes with their labels. Each pane
  gets a shell in its last working directory. A program that supports the Program
  Resume Protocol is restarted. Claude Code resumes today; Codex and OpenCode have
  rules but do not report yet
  ([Session Restore](https://www.superlogical.com/rex/docs/features/session-restore)).

### Keys and configuration

- "Rex doesn't require any configuration, so start using Rex without it and start a
  configuration file when there is something you want to change"
  ([Configuration File](https://www.superlogical.com/rex/docs/customize/config)).
- Defaults are Mac-app shortcuts. Examples: `cmd+t` new tab, `cmd+1`..`9` go to tab,
  `cmd+d` split right, `shift+cmd+d` split down, `alt+cmd+arrow` focus pane,
  `shift+cmd+enter` zoom, `cmd+n` new session, `cmd+k` change session, `cmd+p` Go to
  Anything, `shift+cmd+g` Go to Directory, `shift+cmd+c` copy mode, `cmd+/` sidebar,
  `cmd+.` activity ([Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)).
- There is no prefix key by default. A prefix is the first key of a sequence
  (`ctrl+b>c`). Once a key starts a sequence it no longer reaches the terminal, so
  the docs bind `prefix>prefix` to `pane.send_key`
  ([Key Sequences](https://www.superlogical.com/rex/docs/customize/key-sequences)).
- Key modes ("key tables") cover repeatable binds such as resize
  ([Key Modes](https://www.superlogical.com/rex/docs/customize/key-modes)).
- `init.lua` holds only binds, custom actions, hosts and resume rules. Visual
  settings live in the app
  ([Configuration File](https://www.superlogical.com/rex/docs/customize/config#settings)).

### Extension points

- Custom actions (`rex.action`) appear in the command palette, can be bound, and
  run from the CLI with `rex do`
  ([Custom Actions](https://www.superlogical.com/rex/docs/customize/actions)).
- `rex.ui.input` and `rex.ui.pick` show a native text field or list in the command
  palette. `rex.ui.pick` takes at most 2,000 items. The docs example is an "Open
  project" picker that opens a window in the chosen directory. Prompts need control
  API revision 17
  ([Custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui)).
- The CLI covers `rex new`, `run`, `split`, `send`, `send-key`, `capture`, `wait`,
  `events`
  ([Shell Scripting](https://www.superlogical.com/rex/docs/automate/shell-scripting)).
  Lua scripts and event handlers run with `rex do`
  ([Lua Scripts](https://www.superlogical.com/rex/docs/automate/lua-scripts),
  [Lua Events](https://www.superlogical.com/rex/docs/automate/lua-events)).

### Agents and status

- `rex skill setup` installs a skill and a session-start hook for Claude Code,
  Codex, OpenCode and Pi, so an agent can open tabs, split panes and read screens
  ([Agents](https://www.superlogical.com/rex/docs/automate/agent-skill)).
- Programs report idle, working, blocked, done or failed with OSC 7501. Rex shows
  this on tabs, in the Activity sidebar, and as notifications
  ([Program Status Protocol](https://www.superlogical.com/rex/docs/build/program-status),
  [Mac Settings](https://www.superlogical.com/rex/docs/reference/mac-settings)).

### Remote

- Servers run on Linux, FreeBSD and Windows. Clients exist for macOS; iOS and
  Windows are available to enrolled testers
  ([Installation](https://www.superlogical.com/rex/docs/installation)).
- The recommended transport is SSH: `rex -S ssh://user@host ls`,
  `rex hosts add build ssh://...`. Tailscale is also supported
  ([Remote Access](https://www.superlogical.com/rex/docs/linux/remote-access)).
  Hosts can be declared in `init.lua` with `rex.host{}`
  ([Lua API](https://www.superlogical.com/rex/docs/reference/lua)).

### The vendor's own tmux migration

The Mac app has an "Open Onboarding Session…" action whose search keywords include
"migrate import keybindings theme … ghostty tmux zellij agent"
([Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)). The
app bundle contains the prompt it gives to a coding agent, with one section per
source tool. I read these files locally in
`Rex Beta.app/Contents/Resources/RexApp_RexMigrate.bundle/Contents/Resources/Sections/`
(`tmux.md`, `zellij.md`, `kitty.md`, `ghostty.md`, `wezterm.md`, `iterm2.md`,
`alacritty.md`, `herdr.md`, `prompt.md.tmpl`; app build 2042). They are not
published on the web. The tmux section states:

- The tmux prefix "becomes the first key of every sequence: `bind X cmd` is
  `<prefix>>X`".
- "`bind -r` … Rex has no repeat timer", so each such binding is written twice: as
  a sequence, and in an exclusive key mode named `repeat`.
- "copy-mode and copy-mode-vi bindings, status line options, pane border styles,
  mouse settings, and plugins such as tpm, tmux-resurrect, tmux-yank, tmux-sensible
  and vim-tmux-navigator have no counterpart. Do not approximate them."
- A bind that runs a shell command "migrates only when a `rex.action` that calls
  `rex.exec` does the same thing; otherwise report it."

The shared prompt adds: a line identical to a Rex default is not written, and
`cmd+k` (session picker) is the one default the user is asked about, because other
terminals use it for clear.

**Where Rex deliberately differs from tmux** _(inferred from the sources above)_:
the terminal and the multiplexer are one app, so scrollback, selection and mouse
are native; the default keymap is direct `cmd` shortcuts, not a prefix; session
overview is a sidebar and a palette, not a status line; persistence is a property
of the server, not a plugin; remote is a host list in the app, not `ssh` then
`tmux attach`.

## 3. What users actually do

### The corpus

- GitHub code search for `rex.bind language:Lua path:rex` reports 475 files
  ([query](https://github.com/search?q=rex.bind+language%3ALua+path%3Arex&type=code)).
- I downloaded the Rex config directories of 777 repos (1,899 Lua files). 760
  contain Rex config calls. This full set is biased, because some queries selected
  for features (`rex.ui.pick`, `client.mode.enter`).
- The **generic sample** is the 352 analysed repos returned by the neutral
  `rex.bind` query above. I give generic-sample numbers first and full-corpus
  numbers in brackets.
- Classification is by regular expression. I read about 20 configs in full to check
  it. Treat percentages as approximate (±5 points).

### Patterns and counts

| Pattern                                        | Generic sample (N=352) | Full corpus (N=760) | Example                                                                                     |
| ---------------------------------------------- | ---------------------- | ------------------- | ------------------------------------------------------------------------------------------- |
| Prefix-style key sequence                      | 55%                    | 56%                 | [nicknisi](https://github.com/nicknisi/dotfiles/blob/HEAD/config/rex/init.lua)              |
| Mentions tmux in the config                    | 45%                    | 43%                 | [drewreeve](https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/init.lua)       |
| Binds built-in `session.switch`                | 39%                    | 41%                 | [simonrw](https://github.com/simonrw/dotfiles/blob/HEAD/.config/rex/init.lua)               |
| Calls `rex.session.new_layer` (floating layer) | 40%                    | 40%                 | [d4rkr00t](https://github.com/d4rkr00t/dotfiles/blob/HEAD/rex/init.lua)                     |
| Reads the foreground process cwd               | 37%                    | 36%                 | [classmethod post](https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/) |
| Key modes (`client.mode.enter`)                | 29%                    | 35%                 | [nicknisi](https://github.com/nicknisi/dotfiles/blob/HEAD/config/rex/init.lua)              |
| Only direct binds, with `cmd` keys             | 26%                    | 23%                 | [rokuosan](https://github.com/rokuosan/dotfiles/blob/HEAD/config/rex/init.lua)              |
| lazygit bind                                   | 18%                    | 16%                 | [collindutter](https://github.com/collindutter/dotfiles/blob/HEAD/.config/rex/README.md)    |
| Vim-aware pane focus (process check)           | 18%                    | 18%                 | [anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua)                 |
| Mentions Claude, Codex or OpenCode             | 18%                    | 20%                 | [timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)               |
| Project picker that creates sessions           | 15%                    | 16%                 | [tale](https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua)                     |
| … of which native `rex.ui.pick`                | 7%                     | 9%                  | [rokuosan](https://github.com/rokuosan/dotfiles/blob/HEAD/config/rex/init.lua)              |
| … of which fzf                                 | 8%                     | 7%                  | [drewreeve](https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/actions.lua)    |
| Binds native copy mode                         | 10%                    | 13%                 | [anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua)                 |
| Declares remote hosts (`rex.host`)             | 2%                     | 3%                  | –                                                                                           |
| Mentions a status line                         | 2%                     | 3%                  | –                                                                                           |
| Starts tmux from the config                    | 0                      | 0                   | –                                                                                           |

Other counts (full corpus):

- **Prefix keys:** `ctrl+a` 131, `ctrl+b` 100, `ctrl+space` 56, `ctrl+s` 30. Four
  configs use `ctrl+t`, the prefix in this repo, as their main prefix; one is
  [craftzdog](https://github.com/craftzdog/dotfiles/blob/HEAD/dot_config/rex/init.lua)
  ("migrated from tmux and Herdr (prefix ctrl+t)").
- **Size:** median 88 non-blank, non-comment Lua lines in the generic sample; 75th
  percentile 211; 90th percentile 580. 18 of 352 configs (5%) have 800 lines or
  more.
- **lazygit:** of 125 configs that reference it, about 115 also use a floating
  layer and 6 use only a new tab (approximate; the match is per config, not per
  bind).
- **Migrated configs:** 96 repos contain a "migrated from …" comment, and 86 name
  tmux as a source in a "migrated / ported / carried over from" comment. Many use
  the same header wording ("Migrated from tmux, Ghostty and …"), which matches the
  output of the bundled migration prompt _(inferred link)_. Example:
  [posquit0](https://github.com/posquit0/dotfiles/blob/HEAD/private_dot_config/private_rex/private_key-bindings.lua).
- **tmux inside Rex:** no config starts tmux. At least two detect tmux as the
  foreground process and pass keys through, which implies some nested use, for
  example on remote hosts _(inferred)_:
  [megalithic](https://github.com/megalithic/dotfiles/blob/HEAD/config/rex/init.lua),
  [Alienover](https://github.com/Alienover/dotfiles/blob/HEAD/dotfiles/rex/.config/rex/init.lua).

### tmux migrants compared with the rest

I use "mentions tmux in the config" as a proxy for a tmux migrant (full corpus).

| Pattern                         | Mentions tmux (N=329) | No tmux mention (N=431) |
| ------------------------------- | --------------------- | ----------------------- |
| Prefix-style sequence           | 83%                   | 35%                     |
| Binds built-in `session.switch` | 59%                   | 27%                     |
| Key modes                       | 50%                   | 23%                     |
| Floating layers                 | 45%                   | 36%                     |
| Vim-aware pane focus            | 27%                   | 11%                     |
| Native copy mode binds          | 21%                   | 8%                      |
| Project picker                  | 20%                   | 13%                     |
| Median size (Lua lines)         | 109                   | 98                      |

Reading: tmux migrants keep the prefix and the key layout. They attach the keys to
Rex's built-in actions. Four in five do not build a project picker.

### The typical tmux-migrant config

Seen in [nicknisi](https://github.com/nicknisi/dotfiles/blob/HEAD/config/rex/init.lua),
[simonrw](https://github.com/simonrw/dotfiles/blob/HEAD/.config/rex/init.lua),
[drewreeve](https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/init.lua),
[anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua) and the
[classmethod post](https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/):

- A `prefix` variable and a `bind()` helper.
- `prefix>prefix` to `pane.send_key`.
- `c`, `n`, `p`, `1`..`9`, `,`, `&` to `client.tab.*`.
- `|` and `-` (or `%` and `"`) to `pane.split`; `h/j/k/l` to `pane.focus`; `z` to
  `pane.zoom`; `x` to `pane.close`.
- `s` to the built-in `session.switch`; `(` and `)` to `session.previous` / `next`;
  `$` to `session.rename`.
- A `resize` key mode in place of `bind -r`.
- `[` to `pane.copy_mode.enter`; `r` to `client.config.reload`.
- Rex's `cmd` defaults stay active next to the prefix
  ([collindutter](https://github.com/collindutter/dotfiles/blob/HEAD/.config/rex/README.md):
  "Native macOS shortcuts remain available";
  [LockeAG](https://github.com/LockeAG/rex-config): "Most things also have a direct
  `Cmd` shortcut").

### Project pickers

Two forms exist.

1. **Native prompt.** List directories with `rex.exec`, show them with
   `rex.ui.pick`, find a session with the same label via `session.list`, else
   `session.create` with `cwd`, then `rex.client.queue("session.select", …)`.
   [tale](https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua) does
   this in about 55 lines;
   [rokuosan](https://github.com/rokuosan/dotfiles/blob/HEAD/config/rex/init.lua)
   in about 90.
2. **fzf in a floating layer.** `rex.session.new_layer` runs a shell script:
   `find … | fzf`, then `rex new NAME -c DIR --json`, then
   `rex -C CLIENT do session.select`.
   [drewreeve](https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/actions.lua)
   and [d4rkr00t](https://github.com/d4rkr00t/dotfiles/blob/HEAD/rex/init.lua)
   (zoxide) each use about 20 lines of shell.

Shared packages:

- [almonk/rex-projects](https://github.com/almonk/rex-projects) (32 stars,
  2026-11-18): "New Session in Project…" with project list, worktree choice and
  branch prompt, all on `rex.ui`. The author's GitHub profile links
  alasdairmonk.com, the site of the Superlogical co-founder listed on
  [superlogical.com](https://www.superlogical.com/) _(identity inferred from that
  link)_. Its README says: "Servers older than control API revision 17 have no
  `rex.ui`; the script then does nothing."
- [haxybaxy/rex-sessionizer](https://github.com/haxybaxy/rex-sessionizer) (13
  stars): port of ThePrimeagen's tmux-sessionizer. Default picker is an fzf float;
  `picker = "native"` uses the command palette.
- [fegyi001/rex-navigator](https://github.com/fegyi001/rex-navigator): fzf pickers
  for projects and sessions with a preview, plus a last-session toggle. Tested on
  server preview.20.

One documented move from fzf to native:
[timoclsn's log](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)
says the project picker "moved to" `rex.ui`, "which removed the sessionizer's fzf
popup, the `REX_CLIENT` workaround … and `FZF_DEFAULT_OPTS_FILE`". The same log
lists the limits of `rex.ui.pick`: "no geometry control …, no custom keys, and no
live filtering callback".

### First-hand accounts

| Who, when                                | Came from                                     | What they report                                                                                                                                                                                                                              | Source                                                                                 |
| ---------------------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Blog author, 2026-10-30 (app build 1642) | tmux, prefix `C-q`                            | Moved binds to `ctrl+q>…` sequences. Noted four frictions: shifted symbols are written unshifted; no `bind -r`, used a resize mode; popups rebuilt with `new_layer`; no copy mode then, so opened scrollback in nvim                          | [classmethod](https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/) |
| Dotfiles author, log kept to 2026-11-26  | tmux                                          | Keeps a dated list of "things we built or bent to get tmux behaviour in Rex" and deletes each when Rex ships it. Still open: vim-aware `ctrl+hjkl`, popup helper for lazygit, sessionizer, per-session tab numbers, no toast or clipboard API | [timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)          |
| Blog author, about 2026-10-27            | not stated; compares Rex with tmux and zellij | Liked `cmd+k` session switch ("if nothing matches, you can create a new session right there"), dimmed inactive panes, sidebar tabs, settings UI. Notes there is no prefix by default                                                          | [unvalley](https://unvalley.me/blog/1793111974)                                        |
| HN, 2026-11-04                           | tmux, herdr, mosh, iTerm2                     | "For me it has already replaced tmux, herdr, mosh, claude mobile app, hermex, iTerm2 and even ssh in many cases." Praises the iOS client. No key or config detail                                                                             | [HN 50362804](https://news.ycombinator.com/item?id=50362804)                           |
| HN, 2026-11-05                           | tmux                                          | "I'm using Rex as a multiplexer (recently switched from Tmux)", running several agent projects in parallel                                                                                                                                    | [HN 50377121](https://news.ycombinator.com/item?id=50377121)                           |
| HN, 2026-10-30                           | Ghostty + herdr                               | Replaced both after one week. Local server plus Linux server on a dev box over a tailnet                                                                                                                                                      | [HN 50310251](https://news.ycombinator.com/item?id=50310251)                           |
| HN, 2026-10-27                           | Ghostty                                       | "I have replaced Ghostty with Rex … I really like the iOS app too"                                                                                                                                                                            | [HN 50262768](https://news.ycombinator.com/item?id=50262768)                           |
| HN, 2026-11-04                           | kitty                                         | Stays on kitty: needs `edit-in-kitty` and the image protocol over remote                                                                                                                                                                      | [HN 50364798](https://news.ycombinator.com/item?id=50364798)                           |
| HN, 2026-11-24                           | –                                             | Uses the Mac client daily; wrote an unofficial Linux client                                                                                                                                                                                   | [HN 50631398](https://news.ycombinator.com/item?id=50631398)                           |
| HN, 2026-11-25                           | Termius, mosh                                 | Uses the iOS client; reconnect after sleep works                                                                                                                                                                                              | [HN 50646386](https://news.ycombinator.com/item?id=50646386)                           |

Common points: the reasons people give for staying are persistence, remote and iOS
access, agent status, and polish. None of these accounts describes giving up a
prefix key. None describes regretting a port of tmux keys.

### Friction points reported by tmux migrants

- No `bind -r` repeat timer; use a key mode
  ([bundled guide](#the-vendors-own-tmux-migration),
  [classmethod](https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/)).
- No `#{pane_current_path}` in the action context; read `foreground.cwd` from the
  block's `process` method
  ([timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)).
  36% of configs do this.
- No vim-tmux-navigator; write a process-aware focus action
  ([anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua)).
  The feature request is "deferred" according to
  [timoclsn's log](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)
  (second-hand report of the beta Discord).
- No first-class popup. "add tmux-style popups" is "accepted", not shipped (same
  log, second-hand).
- "Built-in tab actions count tabs across all sessions, tmux counts per session"
  (same log; one source, not verified).
- "Queued session.select for a window created in the same action is dropped" is an
  open bug (same log, second-hand).
- `pane.close` does nothing on the only pane of a tab; tmux's `kill-pane` closes
  the window. Users bind `client.close` or a custom action
  ([drewreeve](https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/init.lua),
  [timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)).
- Session selection from Lua goes through the app
  (`rex.client.queue("session.select")`) and needs Remote Control turned on in the
  app's settings when run from the CLI
  ([Custom Actions](https://www.superlogical.com/rex/docs/customize/actions),
  [haxybaxy](https://github.com/haxybaxy/rex-sessionizer)).
- The same log reports that the team is "working toward a tmux default" keymap
  (second-hand; I found no public statement from the team).

## 4. tmux concept mapping

| tmux concept                                                   | Rex-native equivalent                                                                                                                                                                                                                                           | What users do                                                                                                                                                                                                                                                                                                                                     |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Server and session persistence (`tmux-resurrect`, `continuum`) | The Rex Server holds all state. Client restart restores everything. Server restart restores layout, labels, cwd, and programs that support the resume protocol ([docs](https://www.superlogical.com/rex/docs/features/session-restore))                         | **Native.** No config starts tmux. The bundled guide lists tmux-resurrect as "no counterpart" needed                                                                                                                                                                                                                                              |
| Sessions                                                       | Session = "one project". `session.new` (`cmd+n`), `session.switch` (`cmd+k`), `session.next` / `previous`, sidebar ([actions](https://www.superlogical.com/rex/docs/reference/mac-actions))                                                                     | **Native**, often on a tmux key: 59% of tmux-mentioning configs bind `session.switch`                                                                                                                                                                                                                                                             |
| Windows                                                        | Tabs: `client.tab.new`, `.goto`, `.next`, `.rename`. Defaults `cmd+t`, `cmd+1`..`9`                                                                                                                                                                             | **Replicate keys** on native actions (`prefix>c`, `prefix>1`..`9`)                                                                                                                                                                                                                                                                                |
| Panes                                                          | Blocks: `pane.split.*`, `pane.focus.*`, `pane.zoom`, `pane.resize`, `pane.move.*`, `pane.balance`. Defaults `cmd+d`, `alt+cmd+arrow`                                                                                                                            | **Replicate keys** on native actions                                                                                                                                                                                                                                                                                                              |
| Prefix key                                                     | None by default. Key sequence `a>b`, plus `pane.send_key` for pass-through. "Show key sequence hints" setting ([docs](https://www.superlogical.com/rex/docs/customize/key-sequences), [settings](https://www.superlogical.com/rex/docs/reference/mac-settings)) | **Replicate**: 55% of all configs, 83% of tmux-mentioning ones. `ctrl+a` and `ctrl+b` lead                                                                                                                                                                                                                                                        |
| `bind -r` repeat                                               | Key mode, optionally `exclusive` ([docs](https://www.superlogical.com/rex/docs/customize/key-modes))                                                                                                                                                            | **Native form** (resize mode): 50% of tmux-mentioning configs use modes                                                                                                                                                                                                                                                                           |
| Copy mode (vi)                                                 | Built-in copy mode, `shift+cmd+c`, vi motions, `v` / `V` / `ctrl+v`, `/` search, `y` yank; also native mouse selection and `cmd+f` find ([actions](https://www.superlogical.com/rex/docs/reference/mac-actions))                                                | **Native**, entered from `prefix>[` ([anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua)). Early adopters wrote an nvim-over-`rex capture` stand-in "until Rex ships a native one" ([jorgebef](https://github.com/jorgebef/dotfiles/blob/HEAD/jbef/rex/.config/rex/copy_mode.lua)). tmux copy-mode binds are not migrated |
| Sessionizer                                                    | No built-in project picker. Build with `rex.ui.pick` + `session.create` + `session.select` ([Custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui)), or install [almonk/rex-projects](https://github.com/almonk/rex-projects)                   | **Replicate**, 15 to 20% of configs. Half native prompt, half fzf. Most others use `session.switch` only                                                                                                                                                                                                                                          |
| Popups (`display-popup`)                                       | Floating layers: `rex.session.new_layer{bounds=…}`, `pane.new_floating`, `pane.float`, minimise actions ([Lua API](https://www.superlogical.com/rex/docs/reference/lua))                                                                                        | **Replicate with the native primitive**: 40% of configs. Standard for lazygit                                                                                                                                                                                                                                                                     |
| Status line                                                    | No counterpart (bundled guide). Session and tab names are in the sidebar or tab bar; program state shows on tabs and in Activity                                                                                                                                | **Drop.** About 2% mention one                                                                                                                                                                                                                                                                                                                    |
| Scripting (`tmux send-keys`, `capture-pane`, `wait-for`)       | `rex send`, `rex send-key`, `rex capture`, `rex run --wait`, `rex wait`, `rex events`, Lua via `rex do` ([docs](https://www.superlogical.com/rex/docs/automate/shell-scripting))                                                                                | **Native.** Third-party tools add Rex backends next to tmux, for example [workmux](https://github.com/raine/workmux/blob/HEAD/src/multiplexer/rex/mod.rs)                                                                                                                                                                                         |
| Remote (`ssh` + `tmux attach`)                                 | Rex server on the remote host. `rex -S ssh://host`, `rex hosts add`, `rex.host{}`, "New Session on Host…" (`alt+cmd+n`), Tailscale, iOS client ([docs](https://www.superlogical.com/rex/docs/linux/remote-access))                                              | **Native.** Praised in HN accounts. Only 2 to 3% declare hosts in `init.lua`; hosts can also be added in the app                                                                                                                                                                                                                                  |
| Plugins (tpm, vim-tmux-navigator, tmux-yank)                   | No counterpart (bundled guide)                                                                                                                                                                                                                                  | **Hand-written** vim-aware focus action in 18% of configs; the rest dropped                                                                                                                                                                                                                                                                       |
| `#{pane_current_path}`                                         | `process` block method, `foreground.cwd`                                                                                                                                                                                                                        | **Hand-written helper** in 36% of configs                                                                                                                                                                                                                                                                                                         |
| Config reload                                                  | `client.config.reload`, `rex config reload`                                                                                                                                                                                                                     | **Native**, on `prefix>r`                                                                                                                                                                                                                                                                                                                         |
| Agent awareness (no tmux equivalent)                           | OSC 7501 status, Activity sidebar, `rex skill setup`, Claude Code resume                                                                                                                                                                                        | **Native**; a main reason given for switching                                                                                                                                                                                                                                                                                                     |

## 5. Assessment of the current setup in this repo

Local facts, checked read-only on 2026-11-26:

- The installed app is build 2042 (released 2026-11-18). Its bundled server reports
  `0.1.0-preview.21`, API revision 18. The latest Preview build is 2147
  (2026-11-25, server preview.25)
  ([appcast](https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml)).
- `rex.ui` needs API revision 17
  ([Custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui)). One user
  reports that it reached the Preview channel in Mac "preview.32" on 2026-11-19
  ([timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md)).
  The installed app is one day older. Update before testing `rex.ui.pick`
  _(inferred)_.
- The picker files in this repo were committed between 2026-10-22 and 2026-11-12
  (`git log -- rex`). So they predate the native prompt in Preview.

| Piece                                                                                                                         | Native or common alternative                                                                                                                                                     | Evidence                                                                                                                                                                                                       | Verdict                                                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ctrl+t` prefix and `prefix>prefix` send-key (`rex/init.lua:2`, `:95`)                                                        | Documented pattern. No default binding on the prefix key                                                                                                                         | [Key Sequences](https://www.superlogical.com/rex/docs/customize/key-sequences); 55% of configs                                                                                                                 | **Mainstream.** Not a misuse of Rex. Four configs in the corpus use `ctrl+t` as the prefix                                                                                                                       |
| `prefix>/`, `prefix>-` to `pane.split` (`:77-78`)                                                                             | Built-in action. Defaults `cmd+d`, `shift+cmd+d` also exist                                                                                                                      | [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)                                                                                                                                     | **Covered.** Thin key alias                                                                                                                                                                                      |
| `prefix>r` to `client.config.reload` (`:64`)                                                                                  | Built-in action, no default shortcut                                                                                                                                             | Same                                                                                                                                                                                                           | **Covered.** Common bind                                                                                                                                                                                         |
| `cmd+1`..`9` to `client.tab.goto` (`:88`)                                                                                     | Already the Rex default                                                                                                                                                          | [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)                                                                                                                                     | **Redundant.** The vendor's migration rule is that a line identical to a default is not written                                                                                                                  |
| `cmd+0` to `client.tab.goto { index = -1 }` (`:91`)                                                                           | Default `cmd+0` is Reset Font Size                                                                                                                                               | Same                                                                                                                                                                                                           | **Replaces a default.** I did not find `index = -1` in the docs; not verified                                                                                                                                    |
| `prefix>1`..`9`, `prefix>0` (`:89`, `:92`)                                                                                    | Built-in action on tmux keys                                                                                                                                                     | 35% of configs bind `client.tab.goto`                                                                                                                                                                          | **Mainstream**                                                                                                                                                                                                   |
| `prefix>d` custom `session_picker` (`:82`, picker source `sessions`)                                                          | Built-in `session.switch` ("Change Session…", `cmd+k`): filterable list of sessions                                                                                              | [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions); [unvalley](https://unvalley.me/blog/1793111974); 41% of configs bind it                                                            | **Covered by a built-in.** The configs I read that build their own session list do it to add a preview ([fegyi001](https://github.com/fegyi001/rex-navigator), [LockeAG](https://github.com/LockeAG/rex-config)) |
| `prefix>f` custom `project_picker` (`:81`; `project-picker.lua` 843 lines, `repository-index.lua` 366, `picker-launch.sh` 59) | No built-in. Native building block is `rex.ui.pick`. Drop-in scripts exist                                                                                                       | [Custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui); [almonk/rex-projects](https://github.com/almonk/rex-projects); [tale](https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua) | **No built-in equivalent.** The feature is legitimate; the size is the outlier. See below                                                                                                                        |
| `bind_app` for lazygit and opencode: new tab with a command in the pane's cwd (`:4-61`, `:83-84`)                             | No built-in action takes a command and a cwd. `rex.session.new_window` with `options.command` and `cwd` is the native call. The cwd lookup through `process` is the usual helper | [timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md) ("Found no Lua call that splits a pane with a command and a working directory"); 36% of configs read `foreground.cwd`            | **No built-in equivalent.** The helper is normal. Two parts differ from common practice, below                                                                                                                   |
| tmux binds not ported: `h/j/k/l` focus, arrow resize, `x` kill-pane                                                           | `pane.focus` (`alt+cmd+arrow`), `pane.resize` in a key mode, `client.close` (`cmd+w`)                                                                                            | [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)                                                                                                                                     | **Covered** by defaults or one-line binds                                                                                                                                                                        |
| tmux popups not ported: `kubectx`, `kubens`, `stagehand`; `k9s` window                                                        | `rex.session.new_layer` with a command                                                                                                                                           | 40% of configs use floating layers                                                                                                                                                                             | **Hand-written helper needed**, about 10 lines, shared by all popups ([d4rkr00t](https://github.com/d4rkr00t/dotfiles/blob/HEAD/rex/init.lua))                                                                   |
| tmux status line: session name and kube context                                                                               | No counterpart. Session name is in the sidebar or tab bar                                                                                                                        | Bundled guide                                                                                                                                                                                                  | **No native equivalent** for the kube context. Under 1% of configs touch kube at all                                                                                                                             |
| tmux `copy-mode-vi` `v` / `y`                                                                                                 | Built-in copy mode has `v` and `y` by default                                                                                                                                    | [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions)                                                                                                                                     | **Covered.** Only an entry key is missing (`prefix>[` is the usual choice)                                                                                                                                       |
| catppuccin theme                                                                                                              | "Import Theme File" takes Ghostty and iTerm themes                                                                                                                               | Same                                                                                                                                                                                                           | **Covered**, in app settings, not in `init.lua`                                                                                                                                                                  |

### The project picker in detail

What the custom code does, and whether a native form covers it:

| Capability in `project-picker.lua` / `repository-index.lua`                                                             | Native or common form                                                                                                                                                                                                                                                                                                                                               | Has a native equivalent?                                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Show a filterable list in a floating fzf card sized to the viewport                                                     | `rex.ui.pick` in the command palette                                                                                                                                                                                                                                                                                                                                | **Yes.** No geometry control in the native prompt ([timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md))                                                      |
| Launch plumbing: temp files, hex encoding, `picker-launch.sh`, client lookup, picker slot recovery, stale layer cleanup | Not needed with `rex.ui.pick`: the answer returns into the same Lua function, and every connected app is asked ([Custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui#which-apps-are-asked))                                                                                                                                                        | **Yes**, the need goes away _(inferred from the docs and from timoclsn's report of removing the same workarounds)_                                                                     |
| Login-shell `PATH` and fzf path capture at load                                                                         | Not needed without fzf. `rex.exec` still runs with the server's `PATH`                                                                                                                                                                                                                                                                                              | **Yes** for fzf; `rg` and `git` must still be found                                                                                                                                    |
| Find Git repos under configured roots with `rg`, any depth                                                              | Common form: `find` at fixed depth ([tale](https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua)), `ghq list` ([rokuosan](https://github.com/rokuosan/dotfiles/blob/HEAD/config/rex/init.lua)), `zoxide query -l` ([d4rkr00t](https://github.com/d4rkr00t/dotfiles/blob/HEAD/rex/init.lua)). `rex-projects` scans roots one level deep plus a saved list | **No built-in.** Each user writes this part                                                                                                                                            |
| Disk cache with lock file and detached background refresh                                                               | None of the sampled pickers cache. They scan on each open                                                                                                                                                                                                                                                                                                           | **No native equivalent.** Needed only if the scan is slow. Actions have a 30 second limit ([Custom Actions](https://www.superlogical.com/rex/docs/customize/actions#running-commands)) |
| `ctrl-r` rescan inside the picker                                                                                       | `rex.ui.pick` has "no custom keys" ([timoclsn](https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md))                                                                                                                                                                                                                                                  | **No.** A separate action would be needed                                                                                                                                              |
| Reuse an existing terminal whose cwd is inside the repo, across all sessions                                            | Common form: match the session **label** via `session.list` ([tale](https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua), [haxybaxy](https://github.com/haxybaxy/rex-sessionizer): "sessions are labelled after their directory, so picking it again reopens the same session")                                                                         | **No native equivalent** for the cwd scan. The label match is the common, simpler form                                                                                                 |
| Disambiguate equal repo names with parent path                                                                          | `subtitle` / `detail` fields on `rex.ui.pick` items                                                                                                                                                                                                                                                                                                                 | **Yes**                                                                                                                                                                                |
| More than 2,000 repos                                                                                                   | `rex.ui.pick` limit is 2,000 items                                                                                                                                                                                                                                                                                                                                  | **No**, if the roots hold more                                                                                                                                                         |

Two details in `bind_app` differ from common practice:

- It selects the new tab with `client.list` + `client.perform`. Other configs use
  one line, `rex.client.queue("session.select", { session_id, window_id })`
  ([anmonteiro](https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua),
  [docs](https://www.superlogical.com/rex/docs/customize/actions#calling-other-actions)).
  A second-hand bug report says a queued select "for a window created in the same
  action is dropped", which may be why the longer form exists here _(inferred)_.
- It opens lazygit in a tab. About 115 of 125 configs that launch lazygit use a
  floating layer. This is a preference, not a defect; the tmux config also used a
  window.

### Summary of the assessment

- Keep without concern: the prefix, the split, tab and reload binds. They match
  what the majority does and what the vendor's migration produces.
- Covered by built-ins: the session picker, `cmd+1`..`9`, copy mode, pane focus,
  resize, kill-pane.
- No built-in, but a much smaller common form exists: the project picker (native
  prompt, label-based reuse) and the popup and app launch helpers.
- No native equivalent at all: kube context in a status line; cwd-based session
  reuse; an in-picker rescan key; a persistent repo cache.

## 6. Open questions and evidence gaps

- **Which server runs locally.** Two server copies exist under
  `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/`:
  `2042` reports preview.21 (API revision 18) and `Current` reports preview.14
  (API revision 12, no `rex.ui`). No server was reachable from the research
  sandbox, so I could not check which one is live. `rex server status` shows it.
- **No access to the beta Discord or its MCP server.** Release notes and feature
  request states ("accepted", "deferred") come second-hand from one user's log. The
  docs site says the community MCP is open only to Discord members
  ([llms.txt](https://www.superlogical.com/rex/docs/llms.txt)).
- **No team statement on tmux users beyond the docs and the bundled guide.** The
  "working toward a tmux default" keymap claim is second-hand. I did not review the
  video "Mitchell Hashimoto Talks Rex" ([YouTube](https://www.youtube.com/watch?v=PpwLu8RfPvM))
  or posts on X.
- **No Reddit, X or Bluesky accounts found.** Web searches returned GitHub repos and
  blogs only. Review sites such as bitdoze.com are second-hand and are not used.
- **Corpus limits.** Public dotfiles over-represent people who customise. GitHub
  code search caps results, so 760 is a floor, not the population. Classification
  is by regular expression. Configs change weekly.
- **No retention data.** The configs show what people set up in weeks one to
  seven. They do not show whether prefix users later move to `cmd` defaults.
- **Untested built-ins.** I did not run the app (read-only task). Open: whether
  "Change Session…" can create a session in a chosen directory; what "Go to
  Directory…" opens; how `client.tab.goto` counts tabs with several sessions;
  whether `index = -1` is supported.
- **The HN launch thread of 2026-07-29** (796 points) predates the beta, so it
  cannot hold usage reports; I did not mine it
  ([HN 49098965](https://news.ycombinator.com/item?id=49098965)).

## 7. Sources

All accessed 2026-11-26.

Official:

- https://www.superlogical.com/
- https://www.superlogical.com/updates/public-testing-beginning (2026-10-05)
- https://www.superlogical.com/rex/docs/llms.txt
- https://www.superlogical.com/rex/docs/installation
- https://www.superlogical.com/rex/docs/features/session-restore
- https://www.superlogical.com/rex/docs/customize/config
- https://www.superlogical.com/rex/docs/customize/keyboard-shortcuts
- https://www.superlogical.com/rex/docs/customize/key-sequences
- https://www.superlogical.com/rex/docs/customize/key-modes
- https://www.superlogical.com/rex/docs/customize/actions
- https://www.superlogical.com/rex/docs/customize/custom-ui
- https://www.superlogical.com/rex/docs/automate/cli
- https://www.superlogical.com/rex/docs/automate/agent-skill
- https://www.superlogical.com/rex/docs/automate/lua-scripts
- https://www.superlogical.com/rex/docs/automate/lua-events
- https://www.superlogical.com/rex/docs/automate/shell-scripting
- https://www.superlogical.com/rex/docs/build/program-status
- https://www.superlogical.com/rex/docs/linux/remote-access
- https://www.superlogical.com/rex/docs/reference/lua
- https://www.superlogical.com/rex/docs/reference/mac-actions
- https://www.superlogical.com/rex/docs/reference/mac-settings
- https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml (builds 1497 to 2147)
- https://mitchellh.com/writing/superlogical (founder essay; no workflow detail)
- https://github.com/superlogical
- Local, not on the web: `Rex Beta.app` build 2042, `RexApp_RexMigrate.bundle`
  sections; `rex --help`, `rex version`, `rex skill show` from the bundled CLI.

Team member's personal repo:

- https://github.com/almonk/rex-projects

Community packages:

- https://github.com/haxybaxy/rex-sessionizer
- https://github.com/fegyi001/rex-navigator
- https://github.com/LockeAG/rex-config
- https://github.com/raine/workmux/blob/HEAD/src/multiplexer/rex/mod.rs

User configs read in full:

- https://github.com/timoclsn/dotfiles/blob/HEAD/rex/WORKAROUNDS.md
- https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/init.lua
- https://github.com/anmonteiro/dotfiles/blob/HEAD/rex/README.md
- https://github.com/nicknisi/dotfiles/blob/HEAD/config/rex/init.lua
- https://github.com/simonrw/dotfiles/blob/HEAD/.config/rex/init.lua
- https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/init.lua
- https://github.com/drewreeve/dotfiles/blob/HEAD/rex/.config/rex/actions.lua
- https://github.com/tale/dotfiles/blob/HEAD/modules/rex/init.lua
- https://github.com/rokuosan/dotfiles/blob/HEAD/config/rex/init.lua
- https://github.com/d4rkr00t/dotfiles/blob/HEAD/rex/init.lua
- https://github.com/collindutter/dotfiles/blob/HEAD/.config/rex/README.md
- https://github.com/webhooked/.dotfiles/blob/HEAD/rex/.config/rex/README.md
- https://github.com/craftzdog/dotfiles/blob/HEAD/dot_config/rex/init.lua
- https://github.com/megalithic/dotfiles/blob/HEAD/config/rex/init.lua
- https://github.com/Alienover/dotfiles/blob/HEAD/dotfiles/rex/.config/rex/init.lua
- https://github.com/jorgebef/dotfiles/blob/HEAD/jbef/rex/.config/rex/copy_mode.lua
- https://github.com/posquit0/dotfiles/blob/HEAD/private_dot_config/private_rex/private_key-bindings.lua

Corpus queries (GitHub code search API, two pages of 100 unless noted):

- `rex.bind language:Lua path:rex` (all pages; 475 files, 357 repos: the generic
  sample)
- `client.tab.goto`, `client.mode.enter`, `pane.send_key`, `pane.go_to`,
  `pane.copy_mode.enter`, `client.sidebar.toggle`, `pane.new_floating`,
  `rex.ui.pick`, `rex.ui.input`, `rex.session.new_layer`
- With `language:Lua`: `client.tab.new`, `client.config.reload`,
  `com.superlogical.terminal.shell`, `session.select`
- With `language:Lua path:rex`: `pane.split`, `rex.action`, `session.switch`,
  `pane.focus`, `rex.host`

First-hand accounts:

- https://dev.classmethod.jp/en/articles/reona-superlogical-rex-beta-try/ (app build 1642, 2026-10-30)
- https://unvalley.me/blog/1793111974 (about 2026-10-27)
- https://news.ycombinator.com/item?id=50262768
- https://news.ycombinator.com/item?id=50310251
- https://news.ycombinator.com/item?id=50362804
- https://news.ycombinator.com/item?id=50364798
- https://news.ycombinator.com/item?id=50377121
- https://news.ycombinator.com/item?id=50631398
- https://news.ycombinator.com/item?id=50646386
- https://news.ycombinator.com/item?id=49098965 (launch thread, not mined)
