#import <Foundation/Foundation.h>
#include "DiscordSocialBridge.h"
#define DISCORDPP_IMPLEMENTATION
#include "discordpp.h"

// Every entry point and SDK callback runs on the application's main thread.
static std::shared_ptr<discordpp::Client> client;
static uint64_t generation = 0, expectedUser = 0;
static std::string state = "disconnected";

void MPDiscordDisconnect(void) {
    ++generation;
    if (client) client->Disconnect();
    client.reset(); expectedUser = 0; state = "disconnected";
}

void MPDiscordConfigure(uint64_t applicationID, uint64_t expectedUserID, const char *accessToken) {
    MPDiscordDisconnect();
    if (!applicationID || !expectedUserID || !accessToken || !*accessToken) return;
    expectedUser = expectedUserID;
    auto current = ++generation;
    client = std::make_shared<discordpp::Client>();
    client->SetApplicationId(applicationID);
    state = "connecting";
    client->SetStatusChangedCallback([current](auto status, auto error, auto) {
        if (current != generation) return;
        state = status == discordpp::Client::Status::Ready ? "ready" :
            error != discordpp::Client::Error::None ? "authorization-required" : "connecting";
    });
    client->UpdateToken(discordpp::AuthorizationTokenType::Bearer, accessToken, [current](auto result) {
        if (current != generation || !client) return;
        if (result.Successful()) client->Connect();
        else state = "authorization-required";
    });
}

void MPDiscordPump(void) { discordpp::RunCallbacks(); }

char *MPDiscordCopySnapshot(void) {
    @autoreleasepool {
        NSMutableArray *friends = [NSMutableArray array];
        if (client && state == "ready") {
            auto own = client->GetCurrentUserV2();
            if (!own || own->Id() != expectedUser) {
                client->Disconnect(); state = "account-mismatch";
            } else {
                for (const auto &relationship : client->GetRelationships()) {
                    if (relationship.DiscordRelationshipType() != discordpp::RelationshipType::Friend) continue;
                    auto user = relationship.User();
                    if (!user || !user->Id() || user->Status() == discordpp::StatusType::Blocked) continue;
                    const char *presence = "unknown";
                    switch (user->Status()) {
                        case discordpp::StatusType::Online: presence = "online"; break;
                        case discordpp::StatusType::Idle: presence = "idle"; break;
                        case discordpp::StatusType::Dnd: presence = "dnd"; break;
                        case discordpp::StatusType::Offline:
                        case discordpp::StatusType::Invisible: presence = "offline"; break;
                        default: break;
                    }
                    NSString *name = [NSString stringWithUTF8String:user->DisplayName().c_str()] ?: @"Discord friend";
                    if (!name.length) name = @"Discord friend";
                    [friends addObject:@{@"discordID": [NSString stringWithFormat:@"%llu", (unsigned long long)user->Id()],
                                         @"displayName": name, @"presence": @(presence)}];
                    if (friends.count == 1000) break;
                }
            }
        }
        NSDictionary *snapshot = @{@"state": @(state.c_str()), @"friends": friends};
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return strdup(json.UTF8String ?: "{}");
    }
}

void MPDiscordFreeString(char *value) { free(value); }
