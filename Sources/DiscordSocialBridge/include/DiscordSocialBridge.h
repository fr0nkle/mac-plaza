#ifndef MACPLAZA_DISCORD_SOCIAL_BRIDGE_H
#define MACPLAZA_DISCORD_SOCIAL_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void MPDiscordConfigure(uint64_t applicationID, uint64_t expectedUserID, const char *accessToken);
void MPDiscordPump(void);
char *MPDiscordCopySnapshot(void);
void MPDiscordFreeString(char *value);
void MPDiscordDisconnect(void);
void MPDiscordAuthorizeLocal(uint64_t applicationID, uint64_t expectedUserID, const char *refreshToken);
char *MPDiscordTakeAuthorizationResult(void);
void MPDiscordCancelAuthorization(void);
#ifdef __cplusplus
}
#endif
#endif
