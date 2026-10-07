const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function createTranslator(systemLocale) {
  const context = { Qt: { locale: () => systemLocale } };
  vm.createContext(context);
  vm.runInContext(
    fs.readFileSync(path.join(__dirname, "..", "i18n.js"), "utf8"),
    context,
  );
  return (key, locale, language) => context.t(key, locale, language);
}

const translate = createTranslator({ name: "en_US", uiLanguages: ["en_US"] });

test("Spanish override translates UI strings regardless of system locale", () => {
  assert.equal(translate("addSection", "en_US", "es"), "Nueva tarea");
  assert.equal(translate("cancel", "en_US", "es"), "Cancelar");
  assert.equal(translate("uiLanguageEs", "en_US", "es"), "Español");
});

test("system Spanish locale selects Spanish translations", () => {
  assert.equal(translate("addSection", "es-ES", "system"), "Nueva tarea");
  assert.equal(translate("uiLanguage", "es_ES.UTF-8", "system"), "Idioma de la interfaz");
});

test("Qt Spanish UI language is used when no locale is passed", () => {
  const systemTranslate = createTranslator({ name: "en_US", uiLanguages: ["es-ES"] });
  assert.equal(systemTranslate("addSection", "", "system"), "Nueva tarea");
});

test("preferred English UI language beats Spanish formatting locale", () => {
  const systemTranslate = createTranslator({ name: "es_ES", uiLanguages: ["en-US"] });
  assert.equal(systemTranslate("addSection", "en-US", "system"), "New task");
});

test("English and Russian overrides remain available", () => {
  assert.equal(translate("addSection", "es-ES", "en"), "New task");
  assert.equal(translate("addSection", "es-ES", "ru"), "Новая задача");
});
