"""Shared by extract.py, assemble.py and apply.py in this folder."""
import re

SPECIFIER = re.compile(r"%(?:(\d+)\$)?([-+ 0#]*\d*(?:\.\d+)?)(lld|ld|llu|lu|lf|d|u|f|@|%)")
INTEGER = {"lld", "ld", "llu", "lu", "d", "u"}

# The plural categories each language has (CLDR). A plural item may be answered
# with one string, or with an object holding exactly these keys.
PLURALS = {
    "one other": ("bg bn ca da de el es es-MX fi fr fr-CA gu hi hu it kk kn ml mr nb nl or pa pt pt-PT "
                  "sv ta te tr ur").split(),
    "other": "id ja ko ms th vi zh-Hans zh-Hant".split(),
    "one few many other": "cs pl ru sk uk".split(),
    "one few other": "hr ro".split(),
    "one two few other": "sl".split(),
    "one two other": "he".split(),
    "zero one two few many other": "ar".split(),
}
CATEGORIES = {language: tuple(forms.split()) for forms, languages in PLURALS.items() for language in languages}


def specifiers(text):
    """The arguments a format string takes, as a list of types by position."""
    found, next_position = {}, 1
    for position, _, kind in SPECIFIER.findall(text):
        if kind == "%":
            continue
        index = int(position) if position else next_position
        next_position = index + 1
        found[index] = "int" if kind in INTEGER else "float" if kind in ("f", "lf") else "object"
    return found


def format_problem(english, translation, may_drop_last=False):
    """None when the translation takes the same arguments as the English."""
    wanted, got = specifiers(english), specifiers(translation)
    if got == wanted:
        return None
    if may_drop_last and wanted and got == {k: v for k, v in wanted.items() if k != max(wanted)}:
        return None
    return f"takes {got or 'no arguments'}, English takes {wanted or 'no arguments'}"


def edges(english, translation):
    """The translation with the English string's leading and trailing blanks."""
    head = english[: len(english) - len(english.lstrip())]
    tail = english[len(english.rstrip()):]
    return head + translation.strip() + tail
