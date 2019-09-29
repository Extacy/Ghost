# Redie-Improved
Improved version of Pyro_'s Redie.

Video Demo: <a href="http://www.youtube.com/watch?feature=player_embedded&v=80zsJjaiMtU
" target="_blank"><img src="http://img.youtube.com/vi/80zsJjaiMtU/0.jpg" 
alt="Redie Test Video" width="240" height="180" border="10" /></a>
## Features:
* Noclip
* Autobhop
* Unlimited speed
* View other ghosts in Redie
* Working Unredie
* Players in Redie have access to a menu to toggle their own settings. [\[IMG\]](https://i.imgur.com/Q0tM4MK.png)
* Admins have the ability to see who is in Redie and to teleport to them, unredie them or ban them from Redie. [\[IMG\]](https://i.imgur.com/4qA5ZDL.png)
* Players in Redie can see each other as ghosts. [\[IMG\]](https://i.imgur.com/1pHKv3E.png)

## Commands
* sm_redie -> Turn into a ghost after you die
* sm_unredie -> Return back to spectator
* sm_inredie <player> -> Admin command to see who is in Redie or not. Omit the player name and view a full list of all clients in Redie. Selecting a player will display the Redie Admin Menu.

## ConVars
* sm_redie_enabled 1|0 "Set whether or not Redie is enabled on the server."
* sm_redie_bhop 1|0 "Set whether to enable or disable autobhop in Redie."
* sm_redie_speed 1|0 "Set whether to allow players in Redie to use unlimited speed (sv_enablebunnyhopping)"
* sm_redie_noclip 1|0 "Set whether to allow players in Redie to noclip"
* sm_redie_model 1|0 "Set whether to spawn a fake playermodel so players in Redie can see eachother"
* sm_redie_adverts 1|0 "Set whether to enable or disable Redie adverts (2 min interval)." 

## Server Operators
This plugin may interfere with `sv_autobunnyhopping` / `sv_enablebunnyhopping`. In order for the plugin to not make any unwanted changes to these ConVars, change `sm_redie_bhop 0` and `sm_redie_speed 0`
