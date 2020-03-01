#if defined _ghost_included_
	#endinput
#endif
#define _ghost_included_
 
/**
 * Returns if player is currently a Ghost
 *
 * @param client	The client index
 * @return			True if player is a Ghost, false otherwise.
 */
native bool Ghost_IsGhost(int client);