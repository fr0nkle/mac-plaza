{
  "targets": [{
    "target_name": "plaza_native",
    "sources": ["native/plaza_native.cpp"],
    "include_dirs": ["native/sdk/include"],
    "libraries": ["<(module_root_dir)/native/sdk/lib/release/discord_partner_sdk.lib", "user32.lib", "ole32.lib", "uuid.lib"],
    "defines": ["NAPI_VERSION=8"],
    "msvs_settings": { "VCCLCompilerTool": { "AdditionalOptions": ["/std:c++20", "/EHsc"], "ExceptionHandling": 1 } }
  }]
}
