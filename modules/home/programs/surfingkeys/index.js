const SK = api;

const Colors = {
  background: '#282828',
  foreground: '#ebdbb2',
  tableBody: '#b8bb26',
  inputText: '#d9dce0',
  urlText: '#38971a',
  annotationText: '#b16286',
  focusBackground: '#181818',
  border: '#282828',
  hintBorder: '#3D3E3E',
  accent: '#F92660',
  hintBackground: '#272822',
  hintText: '#A6E22E',
  markBackground: '#A6E22E99',
  cursorBackground: '#F92660',
  separator: '#282828',
  folderBackground: '#188888',
  timestampBackground: '#cc4b9c',
  shadow: 'rgba(0, 0, 0, 0.8)'
};

const Fonts = {
  ui: 'JetBrainsMono Nerd Font, Charcoal, sans-serif',
  hints: 'Maple Mono Freeze'
};

const Layout = {
  omnibarWidth: '60%',
  omnibarTop: '15%',
  omnibarBorderRadius: '10px',
  tabsBorderRadius: '15px',
  tabActiveRadius: '20px',
  popupWidth: '80%',
  popupMaxHeight: '80%',
  statusWidth: '20%'
};

const HintCharacters = 'yuiophjklnm';

function showPopup(message) {
  Front.showPopup(message);
}

function configureKeymaps() {
  SK.mapkey('<ctrl-y>', 'Show me the money', () =>
    showPopup('a well-known phrase uttered by characters in the 1996 film Jerry Maguire (Escape to close).')
  );
  SK.unmap('<ctrl-i>');
  SK.aceVimMap('jk', '<Esc>', 'insert');
}

function configureHints() {
  SK.Hints.setCharacters(HintCharacters);
  SK.Hints.style(
    `border: solid 1px ${Colors.hintBorder}; color: ${Colors.accent}; background: initial; background-color: ${Colors.hintBackground}; font-family: ${Fonts.hints}; box-shadow: 3px 3px 5px ${Colors.shadow};`
  );
  SK.Hints.style(
    `border: solid 1px ${Colors.hintBorder} !important; padding: 1px !important; color: ${Colors.hintText} !important; background: ${Colors.hintBackground} !important; font-family: ${Fonts.hints} !important; box-shadow: 3px 3px 5px ${Colors.shadow} !important;`,
    'text'
  );
}

function configureVisual() {
  SK.Visual.style('marks', `background-color: ${Colors.markBackground};`);
  SK.Visual.style('cursor', `background-color: ${Colors.cursorBackground};`);
}

function configureSettings() {
  settings.newTabPosition = 'last';
}

function buildTheme() {
  return `
.sk_theme {
  font-family: ${Fonts.ui};
  font-size: 10pt;
  background: ${Colors.background};
  color: ${Colors.foreground};
}
.sk_theme tbody { color: ${Colors.tableBody}; }
.sk_theme input { color: ${Colors.inputText}; }
.sk_theme .url { color: ${Colors.urlText}; }
.sk_theme .annotation { color: ${Colors.annotationText}; }

#sk_omnibar {
  width: ${Layout.omnibarWidth};
  left: 50%;
  transform: translateX(-50%);
  box-shadow: 0px 30px 50px ${Colors.shadow};
}
.sk_omnibar_middle {
  top: ${Layout.omnibarTop};
  border-radius: ${Layout.omnibarBorderRadius};
}

.sk_theme .omnibar_highlight { color: ${Colors.foreground}; }
.sk_theme #sk_omnibarSearchResult ul li:nth-child(odd) { background: ${Colors.background}; }

.sk_theme #sk_omnibarSearchResult {
  max-height: 60vh;
  overflow: hidden;
  margin: 0;
}
#sk_omnibarSearchResult > ul { padding: 1em; }
.sk_theme #sk_omnibarSearchResult ul li { margin-block: 0.5rem; padding-left: 0.4rem; }
.sk_theme #sk_omnibarSearchResult ul li.focused {
  background: ${Colors.focusBackground};
  border-color: ${Colors.focusBackground};
  border-radius: 12px;
  position: relative;
  box-shadow: 1px 3px 5px ${Colors.shadow};
}
#sk_omnibarSearchArea > input {
  display: inline-block;
  width: 100%;
  flex: 1;
  font-size: 20px;
  margin-bottom: 0;
  padding: 0 0 0 0.5rem;
  background: transparent;
  border-style: none;
  outline: none;
  padding-left: 18px;
}

#sk_tabs {
  position: fixed;
  top: 0;
  left: 0;
  background-color: rgba(0, 0, 0, 0);
  overflow: auto;
  z-index: 2147483000;
  box-shadow: 0px 30px 50px ${Colors.shadow};
  margin-left: 1rem;
  margin-top: 1.5rem;
  border: solid 1px ${Colors.border};
  border-radius: ${Layout.tabsBorderRadius};
  background-color: ${Colors.background};
  padding-top: 10px;
  padding-bottom: 10px;
}
#sk_tabs div.sk_tab {
  vertical-align: bottom;
  justify-items: center;
  border-radius: 0;
  background: ${Colors.background};
  margin: 0;
  box-shadow: 0 0 0 0 ${Colors.shadow} !important;
  border-top: solid 0 ${Colors.background};
  margin-block: 0;
}
#sk_tabs div.sk_tab:not(:has(.sk_tab_hint)) {
  background-color: ${Colors.focusBackground} !important;
  box-shadow: 1px 3px 5px ${Colors.shadow} !important;
  border: 1px solid ${Colors.focusBackground};
  border-radius: ${Layout.tabActiveRadius};
  position: relative;
  z-index: 1;
  margin-left: 1.8rem;
  padding-left: 0;
  margin-right: 0.7rem;
}
#sk_tabs div.sk_tab_title {
  display: inline-block;
  vertical-align: middle;
  font-size: 10pt;
  white-space: nowrap;
  text-overflow: ellipsis;
  overflow: hidden;
  padding-left: 5px;
  color: ${Colors.foreground};
}
#sk_tabs.vertical div.sk_tab_hint {
  position: inherit;
  left: 8pt;
  margin-top: 3px;
  border: solid 1px ${Colors.hintBorder};
  color: ${Colors.accent};
  background: initial;
  background-color: ${Colors.hintBackground};
  font-family: ${Fonts.hints};
  box-shadow: 3px 3px 5px ${Colors.shadow};
}
#sk_tabs.vertical div.sk_tab_wrap { display: inline-block; margin-left: 0; margin-top: 0; padding-left: 15px; }
#sk_tabs.vertical div.sk_tab_title { min-width: 100pt; max-width: 20vw; }

#sk_usage, #sk_popup, #sk_editor {
  overflow: auto;
  position: fixed;
  width: ${Layout.popupWidth};
  max-height: ${Layout.popupMaxHeight};
  top: 10%;
  left: 10%;
  text-align: left;
  box-shadow: 0px 30px 50px ${Colors.shadow};
  z-index: 2147483298;
  padding: 1rem;
  border: 1px solid ${Colors.border};
  border-radius: 10px;
}

#sk_keystroke {
  padding: 6px;
  position: fixed;
  float: right;
  bottom: 0;
  z-index: 2147483000;
  right: 0;
  background: ${Colors.background};
  color: #fff;
  border: 1px solid ${Colors.focusBackground};
  border-radius: 10px;
  margin-bottom: 1rem;
  margin-right: 1rem;
  box-shadow: 0px 30px 50px ${Colors.shadow};
}

#sk_status {
  position: fixed;
  bottom: 0;
  right: 39%;
  z-index: 2147483000;
  padding: 8px 8px 4px 8px;
  border-radius: 5px;
  border: 1px solid ${Colors.border};
  font-size: 12px;
  box-shadow: 0px 20px 40px 2px rgba(0, 0, 0, 1);
  width: ${Layout.statusWidth};
  margin-bottom: 1rem;
}

#sk_omnibarSearchArea { border-bottom: 0 solid ${Colors.border}; }
#sk_omnibarSearchArea .resultPage { display: inline-block; font-size: 12pt; font-style: italic; width: auto; }
#sk_omnibarSearchResult li div.url { font-weight: normal; white-space: nowrap; color: #aaa; }

.sk_theme .omnibar_highlight { color: #11eb11; font-weight: bold; }
.sk_theme .omnibar_folder {
  border: 1px solid ${Colors.folderBackground};
  border-radius: 5px;
  background: ${Colors.folderBackground};
  color: #aaa;
  box-shadow: 1px 1px 5px rgba(0, 8, 8, 1);
}
.sk_theme .omnibar_timestamp {
  background: ${Colors.timestampBackground};
  border: 1px solid ${Colors.timestampBackground};
  border-radius: 5px;
  color: #aaa;
  box-shadow: 1px 1px 5px rgb(0, 8, 8);
}
#sk_omnibarSearchResult li div.title { text-align: left; max-width: 100%; white-space: nowrap; overflow: auto; }

.sk_theme .separator { color: ${Colors.separator}; }
.sk_theme .prompt {
  color: #aaa;
  background-color: ${Colors.focusBackground};
  border-radius: 10px;
  padding-left: 22px;
  padding-right: 21px;
  font-weight: bold;
  box-shadow: 1px 3px 5px ${Colors.shadow};
}

#sk_status, #sk_find { font-size: 10pt; font-weight: bold; text-align: center; padding-right: 8px; }
#sk_status span[style*="border-right: 1px solid rgb(153, 153, 153);"] { display: none; }
`;
}

function applyTheme() {
  settings.theme = buildTheme();
}

function initialize() {
  configureSettings();
  applyTheme();
  configureHints();
  configureVisual();
  configureKeymaps();
}

initialize();
