# Ghost
Alliedmods Thread: https://forums.alliedmods.net/showthread.php?p=2673662

Video Demo: <a href="http://www.youtube.com/watch?feature=player_embedded&v=8T07u3TYINM
" target="_blank"><img src="http://img.youtube.com/vi/8T07u3TYINM/0.jpg" 
alt="Ghost Test Video" width="240" height="180" border="10" /></a>
## Features:
* Noclip
* Autobhop
* Unlimited speed
* Checkpoint teleports
* Working Unghost / Unredie
* Working trigger_teleports
* Players have access to a menu to toggle their own settings as a ghost. [\[IMG\]](https://i.imgur.com/QOz3Gwt.png)
* English, Russian, and Portuguese translations 

## Commands
* sm_ghost / sm_redie -> Turn into a ghost after you die
* sm_unghost / sm_unredie -> Return back to spectator
* sm_rmenu -> Reopen Ghost Menu

## ConVars
**Config File is located in `csgo/cfg/sourcemod/ghost.cfg`**
* `sm_ghost_enabled 1|0 "Set whether Ghost is enabled on the server."`
* `sm_ghost_bhop 1|0 "Set whether ghosts can autobhop. (sv_autobunnyhopping)"`
* `sm_ghost_speed 1|0 "Set whether ghosts can use unlimited speed (sv_enablebunnyhopping)"`
* `sm_ghost_noclip 1|0 "Set whether ghosts can noclip."`
* `sm_ghost_adverts 1|0 "Set whether chat adverts are enabled."`
* `sm_ghost_adverts_interval 120 "Interval (in seconds) of chat adverts."`

## Server Operators
This plugin may interfere with `sv_autobunnyhopping` / `sv_enablebunnyhopping`. In order for the plugin to not make any unwanted changes to these ConVars, change `sm_ghost_bhop 0` and `sm_ghost_speed 0` 
