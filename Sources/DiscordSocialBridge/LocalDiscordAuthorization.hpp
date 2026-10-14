#pragma once
#include <ctime>
#include <algorithm>
#include <memory>
#include <string>
#include "discordpp.h"

// Shared by the Mac bridge and Windows addon. Tokens never enter roster snapshots.
class PlazaDiscordAuthorization : public std::enable_shared_from_this<PlazaDiscordAuthorization> {
    std::shared_ptr<discordpp::Client> sdk;
    uint64_t revision = 0;
    std::string result;
    static std::string quote(const std::string &value) {
        std::string out = "\"";
        for (unsigned char c : value) {
            switch (c) {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default: if (c >= 32) out += c;
            }
        }
        return out + '"';
    }
    void failed() {
        result = "{\"error\":\"Direct Discord sign-in failed. The Discord application must enable Public Client and register http://127.0.0.1/callback. You can still use service sign-in.\"}";
    }
    discordpp::Client::TokenExchangeCallback exchange(uint64_t appID, uint64_t expected, uint64_t current) {
        std::weak_ptr<PlazaDiscordAuthorization> weak = shared_from_this();
        return [weak, appID, expected, current](auto status, std::string access, std::string refresh, auto, int32_t expires, std::string scopes) {
            auto self = weak.lock();
            if (!self || self->revision != current) return;
            if (!status.Successful() || access.empty() || refresh.empty() || access.size() > 4096 || refresh.size() > 4096 ||
                expires <= 0 || scopes.find("sdk.social_layer_presence") == std::string::npos) { self->failed(); return; }
            self->sdk->FetchCurrentUser(discordpp::AuthorizationTokenType::Bearer, access,
                [weak, appID, expected, current, access, refresh, expires](auto verified, uint64_t id, std::string name) {
                    auto self = weak.lock();
                    if (!self || self->revision != current) return;
                    if (!verified.Successful() || !id || (expected && expected != id)) { self->failed(); return; }
                    self->result = "{\"applicationID\":" + quote(std::to_string(appID)) + ",\"discordID\":" + quote(std::to_string(id)) +
                        ",\"accessToken\":" + quote(access) + ",\"refreshToken\":" + quote(refresh) +
                        ",\"expiresAt\":" + std::to_string(std::time(nullptr) + std::min(expires, 604800)) +
                        ",\"localAuthorization\":true,\"displayName\":" + quote(name) + "}";
                });
        };
    }
public:
    void cancel() {
        ++revision; result.clear();
        if (sdk) sdk->AbortAuthorize();
        sdk.reset();
    }
    void start(uint64_t appID, uint64_t expected, const std::string &refresh = "") {
        cancel(); const auto current = revision;
        if (!appID) { failed(); return; }
        sdk = std::make_shared<discordpp::Client>(); sdk->SetApplicationId(appID);
        if (!refresh.empty()) { sdk->RefreshToken(appID, refresh, exchange(appID, expected, current)); return; }
        auto verifier = sdk->CreateAuthorizationCodeVerifier();
        discordpp::AuthorizationArgs args;
        args.SetClientId(appID); args.SetScopes("identify openid sdk.social_layer_presence"); args.SetCodeChallenge(verifier.Challenge());
        std::weak_ptr<PlazaDiscordAuthorization> weak = shared_from_this();
        sdk->Authorize(args, [weak, current, appID, expected, verifier](auto status, std::string code, std::string redirect) {
            auto self = weak.lock();
            if (!self || self->revision != current) return;
            if (!status.Successful()) { self->failed(); return; }
            self->sdk->GetToken(appID, code, verifier.Verifier(), redirect, self->exchange(appID, expected, current));
        });
    }
    std::string takeResult() { auto next = std::move(result); result.clear(); return next; }
};
