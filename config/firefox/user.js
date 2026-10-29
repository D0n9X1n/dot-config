// Managed by dot-configs (config/firefox/user.js). Firefox reapplies these
// prefs at every start, so edit this file, not about:config.
// The oh-my-firefox theme in the profile's chrome/ folder needs the first one.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Fonts used by the oh-my-firefox theme and for page text. Pages that ask for
// serif get Rec Serif Mt.Adams; everything else uses Rec Sans Mt.Baker.
user_pref("font.language.group", "x-western");
user_pref("font.name.serif.x-western", "Rec Serif Mt.Adams");
user_pref("font.name.serif.zh-CN", "Rec Serif Mt.Adams");
user_pref("font.name.sans-serif.x-western", "Rec Sans Mt.Baker");
user_pref("font.name.sans-serif.zh-CN", "Rec Sans Mt.Baker");
user_pref("font.name.sans-serif.ar", "Rec Sans Mt.Baker");
user_pref("font.name.monospace.x-western", "Rec Mono St.Helens");
user_pref("font.name.monospace.zh-CN", "Rec Mono St.Helens");
user_pref("font.size.variable.x-western", 15);
user_pref("font.size.variable.zh-CN", 14);
user_pref("font.size.variable.ar", 14);
user_pref("font.size.monospace.zh-CN", 14);

// Fingerprinting protection hides fonts in ~/Library/Fonts from pages by
// default. Drop only that target so pages can use the fonts above.
user_pref("privacy.fingerprintingProtection.overrides", "-FontVisibilityLangPack");

// No search or URL-bar suggestions, and no new-tab page.
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.quicksuggest.all", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.suggest.trending", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
