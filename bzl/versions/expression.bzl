# Copyright 2026 M. Boerger, the MBO Works authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Restricted version-function expressions; no arbitrary Starlark evaluation."""

_FUNCTIONS = ["major", "minor", "patch", "prefix", "components"]

def _top_level(text, *, clauses = False):
    depth = 0
    quote = ""
    escaped = False
    positions = []
    operand = False
    for index in range(len(text)):
        char = text[index]
        if clauses and operand:
            if char == ",":
                positions.append(index)
                operand = False
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ["'", '"']:
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                fail("Unbalanced version expression: '{}'".format(text))
        elif depth == 0:
            positions.append(index)
            if clauses and char in "=!<>~":
                operand = True
    if quote or depth:
        fail("Unbalanced version expression: '{}'".format(text))
    return positions

def _split(text, delimiter, *, clauses = False):
    result = []
    start = 0
    for index in _top_level(text, clauses = clauses):
        if text[index] == delimiter:
            result.append(text[start:index].strip())
            start = index + 1
    result.append(text[start:].strip())
    return result

def _comparison(text, operators):
    text = text.strip()
    for index in _top_level(text, clauses = True):
        for op in operators:
            if text[index:].startswith(op):
                return struct(left = text[:index].strip(), op = op, right = text[index + len(op):].strip())
    return struct(left = "", op = "==", right = text)

def _literal(text):
    if text in ["True", "False", "None"]:
        return {"False": False, "None": None, "True": True}[text]
    if text and (text.isdigit() or (text.startswith("-") and text[1:].isdigit())):
        return int(text)
    if len(text) >= 2 and text[0] in ["'", '"'] and text[-1] == text[0]:
        # Version strings contain ASCII syntax; support ordinary quoted literals
        # and the common single-character escapes without evaluating code.
        result = ""
        escaped = False
        escapes = {'"': '"', "'": "'", "\\": "\\", "n": "\n", "r": "\r", "t": "\t"}
        for char in text[1:-1].elems():
            if escaped:
                if char not in escapes:
                    fail("Unsupported version-string escape: '{}'".format(char))
                result += escapes[char]
                escaped = False
            elif char == "\\":
                escaped = True
            else:
                result += char
        if not escaped:
            return result
    fail("Version function arguments must be integers, strings, True, False, None, or version-function calls: '{}'".format(text))

def _parse(text):
    pending = [text.strip()]
    nodes = []

    # Parents precede children; a bounded work queue avoids Starlark recursion.
    for index in range(len(text) + 1):
        if index >= len(pending):
            break
        call = pending[index]
        opening = call.find("(")
        if opening < 1 or not call.endswith(")"):
            fail("Unknown version function or reference: '{}'".format(call))
        name = call[:opening].strip()
        if name not in _FUNCTIONS:
            fail("Unknown version function: '{}'".format(name))
        arguments = call[opening + 1:-1].strip()
        args = []
        kwargs = {}
        keyword_seen = False
        for raw in _split(arguments, ",") if arguments else []:
            pair = _split(raw, "=")
            if len(pair) > 2 or not raw:
                fail("Invalid version function argument: '{}'".format(raw))
            key = pair[0] if len(pair) == 2 else None
            value = pair[-1]
            if key != None:
                if key in kwargs or key == "mode" or not key or not all([char in "abcdefghijklmnopqrstuvwxyz_" for char in key.elems()]):
                    fail("Invalid or duplicate version function keyword: '{}'".format(key))
                keyword_seen = True
            elif keyword_seen:
                fail("Positional version function arguments must precede keyword arguments.")
            if "(" in value and not value.startswith(('"', "'")):
                parsed = struct(node = len(pending))
                pending.append(value)
            else:
                parsed = struct(value = _literal(value))
            if key == None:
                args.append(parsed)
            else:
                kwargs[key] = parsed
        nodes.append(struct(function = name, args = args, kwargs = kwargs))
    return nodes

expression = struct(parse = _parse, clauses = lambda text: _split(text, ",", clauses = True), comparison = _comparison)
