<p align="center"><img src="images/icon.png" width="160" alt="GW Cooldown Pulse icon"></p>

# GW Cooldown Pulse

A World of Warcraft addon that tells you, without you having to watch your
action bars, when something is ready to use again.

When a spell or trinket comes off cooldown, a large, see-through copy of its
icon appears in the middle of your screen. It grows from 1x to 3x its size,
then bursts out to 5x and fades away. The whole animation takes about three
seconds.

Built for **WoW: Forever** (Interface 16001) and also lists **Anniversary 2.5.6**
(Interface 20506).

## Features

- **A pulse for every cooldown.** Any spell in your spellbook with a cooldown,
  and your equipped trinkets, pulse when they become ready. Nothing to set up.
- **Smart defensives.** Self-only defensive spells wait until you can really
  use them again: off cooldown, your buff from them has ended or been
  dispelled, and any lockout debuff (like Forbearance) has gone.
- **Spells for other people pulse on cooldown alone.** Power Word: Shield,
  Fear Ward and Blessing of Protection ignore your own shield and Weakened
  Soul or Forbearance, so you know they're ready for your party.
- **No pile-ups.** Only one icon grows at a time. If several things are ready
  at once, they play one after another, and the animation speeds up (up to 2x)
  to work through the backlog. Spells that share a cooldown, such as Shaman
  shocks, pulse once.
- **Soft, round look.** The icon is cut to a circle with a halo in its own
  colours, so it stays smooth even at five times its size.
- **Settings window.** Size, opacity, glow, animation length, which spells
  pulse, and more, all in one place.
- **Works with secret values.** Newer clients hide cooldown numbers from
  addons. GW Cooldown Pulse only uses the information the game still allows,
  so it doesn't break or throw errors.

## Install

1. Download the latest release from CurseForge, or click **Code > Download ZIP**
   on this page.
2. Put the `GWCooldownPulse` folder in your game's AddOns folder, so you end up
   with:

   ```
   World of Warcraft\_forever_\Interface\AddOns\GWCooldownPulse\GWCooldownPulse.toc
   ```

   If you downloaded the ZIP from GitHub, the folder inside may be called
   `GWCooldownPulse-main`. Rename it to `GWCooldownPulse`.
3. Restart the game. On the character select screen, open **AddOns** and make
   sure **GW Cooldown Pulse** is ticked.

### "Out of date" warning?

The `.toc` lists Interface `16001` and `20506`. If your client uses a
different number, check it in game with:

```
/dump select(4, GetBuildInfo())
```

Then put that number on the `## Interface:` line of `GWCooldownPulse.toc` and
restart the game. You can also tick **Load out of date AddOns** on the AddOns
screen.

## Settings

Type `/cdpulse` to open the settings window. It's also in the game's options
under **AddOns > GW Cooldown Pulse**.

| Setting | What it does | Default |
| --- | --- | --- |
| Icon size | Starting size of the icon. It grows to 5x this. | 64 px |
| Opacity | How solid the icon is at its strongest. | 60% |
| Halo glow | Strength of the coloured halo. 0 turns it off. | 100% |
| Animation length | How long one pulse takes. | 3 s |
| Ignore cooldowns shorter than | Cooldowns shorter than this never pulse. Stops busy spells from pulsing all the time. | 2 s |
| Only while in combat | No pulses outside combat. | Off |
| Include trinkets | Pulse for your two trinket slots. | On |
| Spells that pulse | Untick a spell to silence it. Only spells that can pulse are listed. New spells appear as you learn or cast them. | All on |

The buttons along the bottom:

- **Test** plays a pulse so you can see your settings.
- **Unlock position** shows a blue box you can drag to move the pulse. Click
  **Lock position** when you're done.
- **Defaults** puts every setting and the position back to normal. Your spell
  choices are kept.

## Slash commands

| Command | What it does |
| --- | --- |
| `/cdpulse` | Open or close the settings window |
| `/cdpulse test` | Play a test pulse |
| `/cdpulse move` | Unlock or lock the pulse position |
| `/cdpulse reset` | Reset settings and position (spell choices are kept) |
| `/cdpulse debug [spell name]` | Show what the addon is tracking, and the state of one spell |
| `/cdpulse help` | List the commands |

`/cooldownpulse` works too.

## Defensive spells

These spells only pulse when you can really use them again: off cooldown,
your own buff from them gone, and any lockout debuff gone.

| Class | Spells |
| --- | --- |
| Paladin | Divine Shield, Divine Protection (both wait for Forbearance) |
| Mage | Ice Block, Ice Barrier, Mana Shield, Fire Ward, Frost Ward |
| Warlock | Shadow Ward |
| Druid | Barkskin |
| Warrior | Shield Wall, Shield Block |
| Rogue | Evasion, Cloak of Shadows |
| Hunter | Deterrence |

These spells are usually cast on other people, so they pulse on their
cooldown alone:

| Class | Spells |
| --- | --- |
| Priest | Power Word: Shield, Fear Ward |
| Paladin | Blessing of Protection |

A spell with no cooldown never pulses. For example, if Power Word: Shield has
no cooldown on your client, it won't pulse.

## Good to know

- **Short cooldowns can be busy.** Spells like Judgement or Mortal Strike pulse
  every time. Untick them in `/cdpulse` or raise "Ignore cooldowns shorter
  than".
- **Pulses can be a little late, never early.** If the end of a cooldown is
  hidden under the global cooldown, the addon waits until it's sure. The pulse
  is at most 1.5 seconds late.
- **No pulses at login.** Nothing pulses for the first couple of seconds after
  logging in or a loading screen.
- **Auto attack, Auto Shot and wand Shoot never pulse.**
- **Hidden buffs in combat.** On newer clients, if the game hides buff names
  in combat, a self-only defensive may pulse when its buff ends rather than
  waiting for the lockout debuff.

## Troubleshooting

If something doesn't pulse when you expect:

1. Cast the spell once, then type `/cdpulse debug Spell Name` while it's on
   cooldown and again after. It shows whether the addon can see the cooldown.
2. Check the spell is ticked in `/cdpulse` and its cooldown is longer than
   "Ignore cooldowns shorter than".
3. Turn on Lua error messages with `/console scriptErrors 1` and look for
   errors mentioning GWCooldownPulse.

## Files

| File | Purpose |
| --- | --- |
| `GWCooldownPulse.toc` | Addon metadata |
| `GWCooldownPulse.lua` | Cooldown tracking and the pulse animation |
| `GWCooldownPulse_Config.lua` | The settings window |
| `.pkgmeta` | CurseForge packaging (leaves out the README and images) |

Settings are saved per account in `GWCooldownPulseDB`.

## Licence

[MIT](LICENSE) © 2026 Gary Winstanley
