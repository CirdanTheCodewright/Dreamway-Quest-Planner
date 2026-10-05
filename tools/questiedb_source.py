"""Read QuestieDB through its owned offline pipeline, including static/derived data.

Requires lupa (Lua 5.1). No WoW client database compilation or per-frame hydration.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).parent / ".runtime"))
from lupa.lua51 import LuaRuntime, lua_type


def python_table(value, mapping=False):
    if lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if not mapping and all(isinstance(k, int) and k >= 1 for k in keys):
        return [python_table(value[i]) for i in range(1, int(max(keys, default=0)) + 1)]
    return {k: python_table(value[k]) for k in keys}


def field_value(value, name):
    """Use schema shapes rather than guessing map keys from array length."""
    if name in ("spawns", "waypoints"):
        return python_table(value, mapping=True)
    if lua_type(value) == "table" and name == "triggerEnd":
        return [python_table(value[1]), python_table(value[2], mapping=True)]
    if lua_type(value) == "table" and name == "extraObjectives":
        return [[python_table(extra[1], mapping=True)] +
                [python_table(extra[i]) for i in range(2, max(extra.keys(), default=1) + 1)]
                for _, extra in sorted(value.items())]
    return python_table(value)


def load_questie_categories(version):
    """Execute the consumer's category tables, including names absent from old DBCs."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        categoryL10n = {}
        categoryExpansions = {Era=1,Tbc=2,Wotlk=3,Cata=4,MoP=5,Current=...}
        QuestieLoader = {ImportModule=function(_,name)
            return name == "l10n" and categoryL10n or categoryExpansions
        end}
    ''', {"tbc": 2, "wotlk": 3}.get(version, 1))
    lookups = ROOT / "Questie/Localization/lookups"
    lua.execute((lookups / "lookupZones.lua").read_text(encoding="utf-8"))
    lua.execute((lookups / "lookupQuestCategories.lua").read_text(encoding="utf-8"))
    names = python_table(lua.globals().categoryL10n.questCategoryLookup, mapping=True)
    groups = {int(key): python_table(value, mapping=True)
              for key, value in lua.globals().categoryL10n.zoneCategoryLookup.items()}
    names.update({key: label for group in groups.values() for key, label in group.items() if key < 0})
    return names, groups


def load_flavor(name):
    previous = Path.cwd()
    try:
        os.chdir(ROOT / "QuestieDB")
        lua = LuaRuntime(unpack_returned_tuples=True)
        loaded = lua.execute('''
            local config = dofile("src/config.lua")
            local name = ...
            local flavor = config.flavorByName[name == "SoD" and "Vanilla" or name]
            local loaded = dofile("generator/flavor.lua").load(flavor)
            if name == "SoD" then
                C_Seasons.GetActiveSeason = function() return 2 end
                local runtime = dofile("generator/runtime.lua")
                local lib = runtime.build()
                runtime.loadCorrections(lib, flavor)
                for _, entry in ipairs(lib.Corrections.Select({dynamic=true})) do
                    -- A catalogue spans all characters; do not bake faction/session policy.
                    if entry.name:match("^Sod/") and not entry.name:find("Faction") then
                        lib.Corrections.MergeInto(loaded[entry.datatype].entities, entry.func(), entry.options, entry)
                    end
                end
                dofile("generator/derived.lua").run(loaded, flavor)
            end
            local context = dofile("generator/corrections.lua").prepare(flavor)
            -- The preparation above is independent of the loader's cached registry;
            -- capture ordering hints while executing owned providers, not by parsing text.
            return loaded, context.lib.CorrectionCompat.objectiveFirst
        ''', name)
        loaded, objective_first = loaded
        result = {}
        result["objectiveFirst"] = {
            label: set(objective_first[key].keys()) if objective_first[key] else set()
            for label, key in (("object", "objectObjectiveFirst"), ("item", "itemObjectiveFirst"),
                               ("killcredit", "killCreditObjectiveFirst"), ("spell", "spellObjectiveFirst"),
                               ("event", "eventObjectiveFirst"))
        }
        for entity in ("Quest", "Npc", "Object", "Item"):
            data = loaded[entity]
            count = data.meta.fieldCount
            result[entity] = {id: [field_value(row[i], data.meta.names[i]) for i in range(1, count + 1)]
                              for id, row in data.entities.items()}
        return result
    finally:
        os.chdir(previous)
