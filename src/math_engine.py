# Program: archi - math_engine.py
# Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
# Last Modified: 2026-11-18
# Purpose: Small helper program that safely parses one math or logic expression sent as JSON on stdin and prints the SymPy result as JSON; it is started once per request by the Archi MathEngine class.

# == Safety limits: cap this process's memory and CPU time so a bad request cannot hang or flood the computer ==
"""Bounded, non-evaluating expression front end for SymPy. One request per process."""
import ast
import json
import math
import sys

# The resource module only exists on Unix-like systems, so skip the limits if it is missing.
try:
    import resource
    # Limit memory to 512 MiB (1024**2 bytes per MiB); the pair is (soft limit, hard limit).
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
    # Limit CPU time to 4 seconds.
    resource.setrlimit(resource.RLIMIT_CPU, (4, 4))
except ImportError:
    pass

# == Imports of the math library (SymPy) used for the actual algebra ==
import sympy as sp
from sympy.core.relational import Relational


def matrix(value):
    """Check that value is a list of 1 to 8 equal-length rows (each 1 to 8 long) and return it as a SymPy Matrix; otherwise raise ValueError."""
    # Reject anything that is not a non-empty list, or has more than 8 rows.
    if not isinstance(value, list) or not value or len(value) > 8:
        raise ValueError("A matrix needs 1 to 8 rows")
    # Every row must itself be a non-empty list with at most 8 entries.
    if any(not isinstance(row, list) or not row or len(row) > 8 for row in value):
        raise ValueError("A matrix needs 1 to 8 columns")
    # Turn the row lengths into a set; more than one distinct length means the rows are ragged.
    if len({len(row) for row in value}) != 1:
        raise ValueError("Matrix rows must have equal length")
    # All checks passed, so build the matrix.
    return sp.Matrix(value)


# == Allow-lists: the only function names and constants an expression may use. Anything else is rejected. ==
FUNCTIONS = {
    "sin": sp.sin, "cos": sp.cos, "tan": sp.tan,
    "asin": sp.asin, "acos": sp.acos, "atan": sp.atan,
    "sinh": sp.sinh, "cosh": sp.cosh, "tanh": sp.tanh,
    "sqrt": sp.sqrt, "exp": sp.exp, "log": sp.log,
    "Abs": sp.Abs, "Rational": sp.Rational, "Matrix": matrix,
    "Eq": sp.Eq, "And": sp.And, "Or": sp.Or, "Not": sp.Not,
    "Xor": sp.Xor, "Implies": sp.Implies, "Equivalent": sp.Equivalent,
}
# Named constants: pi, Euler's number, the imaginary unit, infinity, and boolean True/False.
CONSTANTS = {"pi": sp.pi, "E": sp.E, "I": sp.I, "oo": sp.oo,
             "True": sp.true, "False": sp.false}


def parse_expression(text):
    """Turn the text of an expression into a SymPy object by walking its syntax tree, allowing only approved node types (never calls eval), and raise ValueError for anything unsafe or too big."""
    # Basic input checks: must be a non-empty string of at most 1024 characters.
    if not isinstance(text, str) or not text.strip() or len(text) > 1024:
        raise ValueError("Expression must contain 1 to 1024 characters")
    # Parse the text into a Python syntax tree without running it ("eval" mode means a single expression).
    tree = ast.parse(text, mode="eval")
    # Count every node in the tree and refuse expressions that are too large.
    if sum(1 for _ in ast.walk(tree)) > 160:
        raise ValueError("Expression is too large")

    def visit(node, depth=0):
        """Recursively convert one syntax-tree node (and its children) into a SymPy object; depth tracks how deeply nested we are."""
        # Stop runaway nesting.
        if depth > 24:
            raise ValueError("Expression nesting limit reached")
        # Shortcut: convert a child node one level deeper.
        child = lambda item: visit(item, depth + 1)
        # Numbers and True/False literals.
        if isinstance(node, ast.Constant):
            if isinstance(node.value, bool):
                return sp.true if node.value else sp.false
            if isinstance(node.value, int) and len(str(abs(node.value))) <= 100:
                return sp.Integer(node.value)
            if isinstance(node.value, float) and math.isfinite(node.value):
                return sp.Float(node.value)
            raise ValueError("Only finite numeric literals are allowed")
        # Variable names: known constants first, otherwise a plain ASCII symbol (no leading underscore, max 32 characters).
        if isinstance(node, ast.Name):
            if node.id in CONSTANTS:
                return CONSTANTS[node.id]
            if not node.id.isascii() or node.id.startswith("_") or len(node.id) > 32:
                raise ValueError("Invalid symbol name")
            return sp.Symbol(node.id)
        # Square brackets become a Python list (used for matrices), at most 8 items.
        if isinstance(node, ast.List):
            if len(node.elts) > 8:
                raise ValueError("Matrix dimension limit reached")
            return [child(item) for item in node.elts]
        # Unary operators: minus, plus, and ~ (used here as logical NOT).
        if isinstance(node, ast.UnaryOp):
            value = child(node.operand)
            if isinstance(node.op, ast.USub): return -value
            if isinstance(node.op, ast.UAdd): return value
            if isinstance(node.op, ast.Invert): return sp.Not(value)
        # Binary operators: arithmetic and the bitwise symbols & | ^ which are used as logical AND, OR, XOR.
        if isinstance(node, ast.BinOp):
            left, right = child(node.left), child(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
            # Powers are checked so a huge numeric exponent cannot make the calculation explode.
            if isinstance(node.op, ast.Pow):
                if right.is_number and (right.is_real is not True or abs(right) > 64):
                    raise ValueError("Numeric exponent limit is 64")
                return left ** right
            if isinstance(node.op, ast.BitAnd): return sp.And(left, right)
            if isinstance(node.op, ast.BitOr): return sp.Or(left, right)
            if isinstance(node.op, ast.BitXor): return sp.Xor(left, right)
        # Function calls are allowed only for plain names in the FUNCTIONS list, without keyword arguments, and with at most 8 arguments.
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in FUNCTIONS:
                raise ValueError("Function is not permitted")
            if node.keywords or len(node.args) > 8:
                raise ValueError("Unsupported function arguments")
            return FUNCTIONS[node.func.id](*[child(arg) for arg in node.args])
        # Comparisons such as ==, !=, <, <=, >, >= (one operator only) map to SymPy relations.
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            operators = {ast.Eq: sp.Eq, ast.NotEq: sp.Ne, ast.Lt: sp.Lt,
                         ast.LtE: sp.Le, ast.Gt: sp.Gt, ast.GtE: sp.Ge}
            operator = operators.get(type(node.ops[0]))
            if operator:
                return operator(child(node.left), child(node.comparators[0]))
        # Any other kind of syntax is refused.
        raise ValueError("Unsupported expression syntax")

    # Start the walk at the body of the parsed expression.
    return visit(tree.body)


def calculate(request):
    """Run the requested operation (simplify, differentiate, solve, etc.) on the expression in the request dictionary and return a dict with ok and result."""
    # Parse and validate the expression text.
    expression = parse_expression(request.get("expression"))
    # The variable to differentiate/integrate/solve for; defaults to x.
    name = request.get("variable", "x")
    # Validate the variable name the same way symbol names are validated.
    if not isinstance(name, str) or not name.isascii() or not name.isidentifier() or name.startswith("_") or len(name) > 32:
        raise ValueError("Invalid variable")
    variable = sp.Symbol(name)
    operation = request.get("operation")
    # Boolean operations need true/false propositions, not arithmetic comparisons.
    if operation in {"Boolean simplify", "Satisfiable"}:
        if not isinstance(expression, sp.logic.boolalg.Boolean) or expression.has(Relational):
            raise ValueError("Boolean logic requires propositions, not arithmetic constraints")
    # Table mapping each operation name to a function that computes it; lambdas make sure only the chosen one runs.
    operations = {
        "Simplify": lambda: sp.simplify(expression),
        "Expand": lambda: sp.expand(expression),
        "Factor": lambda: sp.factor(expression),
        "Differentiate": lambda: sp.diff(expression, variable),
        "Integrate": lambda: sp.integrate(expression, variable),
        "Solve = 0": lambda: sp.solve(expression, variable),
        # Matrix operations accept either a list of rows (converted first) or an existing Matrix.
        "Determinant": lambda: matrix(expression).det() if isinstance(expression, list) else expression.det(),
        "Inverse": lambda: matrix(expression).inv() if isinstance(expression, list) else expression.inv(),
        "Eigenvalues": lambda: matrix(expression).eigenvals() if isinstance(expression, list) else expression.eigenvals(),
        "Boolean simplify": lambda: sp.simplify_logic(expression),
        "Satisfiable": lambda: sp.satisfiable(expression),
    }
    # Reject operation names that are not in the table.
    if operation not in operations:
        raise ValueError("Unknown operation")
    # Run the chosen operation and turn the answer into text.
    result = str(operations[operation]())
    # An indefinite integral is only defined up to a constant, so add + C.
    if operation == "Integrate":
        result += " + C"
    # Refuse to return a result that is too long to display.
    if len(result) > 16000:
        raise ValueError("Result exceeds the display budget")
    # Report success.
    return {"ok": True, "result": result}


# == Program entry point: read one JSON request from stdin, answer with one JSON line on stdout ==
if __name__ == "__main__":
    try:
        # Read at most 8193 bytes so we can detect oversized requests without reading everything.
        raw = sys.stdin.buffer.read(8193)
        if len(raw) > 8192:
            raise ValueError("Request is too large")
        # Run the calculation on the decoded JSON request.
        result = calculate(json.loads(raw))
    # Any failure (bad input, math error, limit hit) is reported back as an error message, trimmed to 300 characters.
    except Exception as error:
        result = {"ok": False, "error": str(error)[:300]}
    # Print the answer as a single line of JSON for the C++ side to read.
    print(json.dumps(result))
