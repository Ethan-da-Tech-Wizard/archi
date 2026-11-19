# ==============================================================================
# Program: math_engine.py
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 18, 2026
# Purpose: Bounded, non-evaluating expression front end for SymPy calculations.
#          Safely parses mathematical input strings into an Abstract Syntax Tree (AST),
#          enforces strict execution limits and sandboxing (AST node limit, depth limit),
#          and computes algebraic operations such as simplification, differentiation,
#          integration, and matrix determinants without using unsafe eval().
#
# How it fits: MathEngine.h (C++) starts this script as a separate process
# (`python -I math_engine.py`, interpreter path baked in by CMake as
# ARCHI_MATH_PYTHON/ARCHI_MATH_SCRIPT), writes ONE JSON request to stdin and
# reads ONE JSON reply from stdout. The "Calculate" dialog in
# ProjectWorkspace.qml is the only user.
#
# Protocol:
#   in : {"expression": str, "operation": str, "variable": str}   (<= 8192 bytes)
#   out: {"ok": true, "result": str}  or  {"ok": false, "error": str}
#
# Security model: user text is never passed to eval()/exec() or sympify().
# It is parsed to a Python AST and only whitelisted node types are rebuilt
# into SymPy objects (see parse_expression), with limits on length, node
# count, nesting depth, integer size and exponent. The process also caps its
# own memory and CPU time below; MathEngine.h adds a 6 s wall-clock kill and
# a 64 KiB output cap as a second layer.
#
# Known limits: Windows has no `resource` module, so only the C++-side
# timeout protects there. Requires the `sympy` package in the virtualenv at
# `.venv-math/` next to the sources.
# ==============================================================================
"""Bounded, non-evaluating expression front end for SymPy. One request per process."""
import ast
import json
import math
import sys

# Hard OS limits: 512 MiB address space and 4 s CPU. They stop a pathological
# expression (e.g. a huge integral) from freezing the machine even if the
# parent's timer were somehow delayed. Missing on Windows, hence the guard.
try:
    import resource
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CPU, (4, 4))
except ImportError:
    pass

import sympy as sp
from sympy.core.relational import Relational


def matrix(value):
    """Builds a SymPy Matrix from a nested list, enforcing size limits.

    Args:
        value: List of equal-length, non-empty lists (rows), at most 8x8.

    Returns:
        sympy.Matrix.

    Raises:
        ValueError: if the shape is empty, larger than 8x8 or ragged.
    """
    # 8x8 keeps determinants/eigenvalues cheap; larger symbolic matrices can
    # take unbounded time.
    if not isinstance(value, list) or not value or len(value) > 8:
        raise ValueError("A matrix needs 1 to 8 rows")
    if any(not isinstance(row, list) or not row or len(row) > 8 for row in value):
        raise ValueError("A matrix needs 1 to 8 columns")
    if len({len(row) for row in value}) != 1:
        raise ValueError("Matrix rows must have equal length")
    return sp.Matrix(value)


# Whitelist of callable names allowed in expressions. Anything not listed
# (including attribute access and imports) is rejected as "not permitted".
FUNCTIONS = {
    "sin": sp.sin, "cos": sp.cos, "tan": sp.tan,
    "asin": sp.asin, "acos": sp.acos, "atan": sp.atan,
    "sinh": sp.sinh, "cosh": sp.cosh, "tanh": sp.tanh,
    "sqrt": sp.sqrt, "exp": sp.exp, "log": sp.log,
    "Abs": sp.Abs, "Rational": sp.Rational, "Matrix": matrix,
    "Eq": sp.Eq, "And": sp.And, "Or": sp.Or, "Not": sp.Not,
    "Xor": sp.Xor, "Implies": sp.Implies, "Equivalent": sp.Equivalent,
}
# Whitelist of bare names that mean constants rather than symbols.
CONSTANTS = {"pi": sp.pi, "E": sp.E, "I": sp.I, "oo": sp.oo,
             "True": sp.true, "False": sp.false}


def parse_expression(text):
    """Converts user text into a SymPy expression without evaluating code.

    Args:
        text: Expression such as ``(x + 1)**3`` or ``[[1, 2], [3, 4]]``.

    Returns:
        A SymPy object (or a plain list for matrix literals).

    Raises:
        ValueError: for empty/oversized input, too many nodes (> 160), nesting
            deeper than 24, unsupported syntax, huge numbers or exponents.
        SyntaxError: if the text is not valid Python expression syntax.
    """
    # 1 KiB is far above any realistic hand-typed formula.
    if not isinstance(text, str) or not text.strip() or len(text) > 1024:
        raise ValueError("Expression must contain 1 to 1024 characters")
    # mode="eval" accepts a single expression only: no statements, imports or
    # assignments can get through.
    tree = ast.parse(text, mode="eval")
    # Total node count bounds work for the later SymPy calls.
    if sum(1 for _ in ast.walk(tree)) > 160:
        raise ValueError("Expression is too large")

    def visit(node, depth=0):
        """Translates one AST node (recursively) into a SymPy value.

        Args:
            node: ast node to convert.
            depth: current nesting level; limited so a crafted deep tree cannot
                exhaust Python's recursion limit.

        Raises:
            ValueError: for any construct outside the whitelist.
        """
        if depth > 24:
            raise ValueError("Expression nesting limit reached")
        # Helper that recurses one level deeper.
        child = lambda item: visit(item, depth + 1)
        if isinstance(node, ast.Constant):
            # Checked before int: bool is a subclass of int in Python.
            if isinstance(node.value, bool):
                return sp.true if node.value else sp.false
            # <= 100 digits stops 10**N style memory bombs written as literals.
            if isinstance(node.value, int) and len(str(abs(node.value))) <= 100:
                return sp.Integer(node.value)
            # nan/inf literals are rejected; infinity is available only as the name `oo`.
            if isinstance(node.value, float) and math.isfinite(node.value):
                return sp.Float(node.value)
            raise ValueError("Only finite numeric literals are allowed")
        if isinstance(node, ast.Name):
            if node.id in CONSTANTS:
                return CONSTANTS[node.id]
            # Block dunder-style and private names and non-ASCII look-alikes.
            if not node.id.isascii() or node.id.startswith("_") or len(node.id) > 32:
                raise ValueError("Invalid symbol name")
            return sp.Symbol(node.id)
        # Lists only appear as matrix literals; cap the row count early.
        if isinstance(node, ast.List):
            if len(node.elts) > 8:
                raise ValueError("Matrix dimension limit reached")
            return [child(item) for item in node.elts]
        if isinstance(node, ast.UnaryOp):
            value = child(node.operand)
            if isinstance(node.op, ast.USub): return -value
            if isinstance(node.op, ast.UAdd): return value
            if isinstance(node.op, ast.Invert): return sp.Not(value)
        if isinstance(node, ast.BinOp):
            left, right = child(node.left), child(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
            if isinstance(node.op, ast.Pow):
                # Exponent guard: a numeric exponent must be real and |n| <= 64, otherwise
                # x**(10**9) style input would expand to something enormous.
                if right.is_number and (right.is_real is not True or abs(right) > 64):
                    raise ValueError("Numeric exponent limit is 64")
                return left ** right
            if isinstance(node.op, ast.BitAnd): return sp.And(left, right)
            if isinstance(node.op, ast.BitOr): return sp.Or(left, right)
            if isinstance(node.op, ast.BitXor): return sp.Xor(left, right)
        # Only plain calls to whitelisted names; no keywords, no `obj.method(...)`.
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in FUNCTIONS:
                raise ValueError("Function is not permitted")
            if node.keywords or len(node.args) > 8:
                raise ValueError("Unsupported function arguments")
            return FUNCTIONS[node.func.id](*[child(arg) for arg in node.args])
        # Chained comparisons (a < b < c) are unsupported; only single relations.
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            operators = {ast.Eq: sp.Eq, ast.NotEq: sp.Ne, ast.Lt: sp.Lt,
                         ast.LtE: sp.Le, ast.Gt: sp.Gt, ast.GtE: sp.Ge}
            operator = operators.get(type(node.ops[0]))
            if operator:
                return operator(child(node.left), child(node.comparators[0]))
        # Reached by any node type not handled above (lambda, subscript, f-string,
        # attribute, etc.), including unsupported operators such as `//` or `%`.
        raise ValueError("Unsupported expression syntax")

    return visit(tree.body)


def calculate(request):
    """Runs one requested operation and returns the reply dictionary.

    Args:
        request: Decoded JSON object with ``expression``, ``operation`` and
            optional ``variable`` (default ``"x"``).

    Returns:
        ``{"ok": True, "result": <str>}``. The result text is SymPy's string
        form; integrals get `` + C`` appended.

    Raises:
        ValueError: invalid variable name, unknown operation, boolean
            operation on arithmetic input, or a result over 16000 chars.
            (The caller turns exceptions into ``{"ok": False, ...}``.)
    """
    # Calculus variable: same restrictions as symbol names in the parser.
    expression = parse_expression(request.get("expression"))
    name = request.get("variable", "x")
    if not isinstance(name, str) or not name.isascii() or not name.isidentifier() or name.startswith("_") or len(name) > 32:
        raise ValueError("Invalid variable")
    variable = sp.Symbol(name)
    operation = request.get("operation")
    # Boolean operations must receive propositions; reject inequalities such as
    # x > 1 because SymPy's logic routines would treat them inconsistently.
    if operation in {"Boolean simplify", "Satisfiable"}:
        if not isinstance(expression, sp.logic.boolalg.Boolean) or expression.has(Relational):
            raise ValueError("Boolean logic requires propositions, not arithmetic constraints")
    # Dispatch table of lambdas: nothing is computed until the chosen entry is
    # called, so unused operations cost nothing. Operation names are the exact
    # strings shown in the QML drop-down.
    operations = {
        "Simplify": lambda: sp.simplify(expression),
        "Expand": lambda: sp.expand(expression),
        "Factor": lambda: sp.factor(expression),
        "Differentiate": lambda: sp.diff(expression, variable),
        "Integrate": lambda: sp.integrate(expression, variable),
        "Solve = 0": lambda: sp.solve(expression, variable),
        # Matrix operations accept either a raw list literal or an already built Matrix.
        "Determinant": lambda: matrix(expression).det() if isinstance(expression, list) else expression.det(),
        "Inverse": lambda: matrix(expression).inv() if isinstance(expression, list) else expression.inv(),
        "Eigenvalues": lambda: matrix(expression).eigenvals() if isinstance(expression, list) else expression.eigenvals(),
        "Boolean simplify": lambda: sp.simplify_logic(expression),
        "Satisfiable": lambda: sp.satisfiable(expression),
    }
    # Unknown names fail here, before any SymPy work, so the user sees a clear error.
    if operation not in operations:
        raise ValueError("Unknown operation")
    result = str(operations[operation]())
    # SymPy omits the arbitrary constant of integration.
    if operation == "Integrate":
        result += " + C"
    # Keeps the reply well under MathEngine.h's 64 KiB output cap.
    if len(result) > 16000:
        raise ValueError("Result exceeds the display budget")
    return {"ok": True, "result": result}


# Script entry: read request, compute, print exactly one JSON line.
if __name__ == "__main__":
    # Everything, including SymPy internals, is reported as JSON so the C++ side
    # never has to parse a traceback; messages are truncated to 300 characters.
    try:
        # Read one byte beyond 8 KiB so an oversize request is detected, not truncated.
        raw = sys.stdin.buffer.read(8193)
        if len(raw) > 8192:
            raise ValueError("Request is too large")
        result = calculate(json.loads(raw))
    except Exception as error:
        result = {"ok": False, "error": str(error)[:300]}
    print(json.dumps(result))
