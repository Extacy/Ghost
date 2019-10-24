# Ghost
Improved version of Pyro_'s Redie.

Video Demo: <a href="http://www.youtube.com/watch?feature=player_embedded&v=4SenGodqBFA"
" target="_blank"><img src="http://img.youtube.com/vi/4SenGodqBFA/0.jpg" 
alt="Redie Test Video" width="240" height="180" border="10" /></a>
## Features:
* Noclip
* Autobhop
* Unlimited speed
* View other ghosts
* Working Unghost / Unredie
* Working trigger_teleports
* Players have access to a menu to toggle their own settings as a ghost. [\[IMG\]](https://i.imgur.com/AcEPss2.png)
* Admins have the ability to see who is a Ghost and to teleport to them, force them to return to spectator, or ban them from using Ghost. [\[IMG\]](https://i.imgur.com/1m2JqeY.png)
* Players can see each other as ghosts. (disabled by default) [\[IMG\]](https://i.imgur.com/1pHKv3E.png)

## Commands
* sm_ghost / sm_redie -> Turn into a ghost after you die
* sm_unghost / sm_unredie -> Return back to spectator
* sm_inghost / sm_inredie <player> -> Admin command to see who is in Ghost/Redie or not. Omit the player name and view a full list of all clients in Ghost/Redie. Selecting a player will display the Admin Menu.

## ConVars
* `sm_ghost_enabled 1|0 "Set whether Ghost is enabled on the server."`
* `sm_ghost_bhop 1|0 "Set whether ghosts can autobhop. (sv_autobunnyhopping)"`
* `sm_ghost_speed 1|0 "Set whether ghosts can use unlimited speed (sv_enablebunnyhopping)"`
* `sm_ghost_noclip 1|0 "Set whether ghosts can noclip."`
* `sm_ghost_model 1|0 "Set whether to spawn a ghost model so players can see each other."`
* `sm_ghost_custom_model 1|0 "Set whether to use a custom or default playermodel for Ghosts."`
* `sm_ghost_adverts 1|0 "Set whether chat adverts are enabled."`
* `sm_ghost_adverts_interval 120 "Interval (in seconds) of chat adverts."`

## Server Operators
This plugin may interfere with `sv_autobunnyhopping` / `sv_enablebunnyhopping`. In order for the plugin to not make any unwanted changes to these ConVars, change `sm_ghost_bhop 0` and `sm_ghost_speed 0` 
