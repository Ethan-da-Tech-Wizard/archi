"""Bounded, non-evaluating expression front end for SymPy. One request per process."""
import ast
import json
import math
import sys

try:
    import resource
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CPU, (4, 4))
except ImportError:
    pass

import sympy as sp
from sympy.core.relational import Relational


def matrix(value):
    if not isinstance(value, list) or not value or len(value) > 8:
        raise ValueError("A matrix needs 1 to 8 rows")
    if any(not isinstance(row, list) or not row or len(row) > 8 for row in value):
        raise ValueError("A matrix needs 1 to 8 columns")
    if len({len(row) for row in value}) != 1:
        raise ValueError("Matrix rows must have equal length")
    return sp.Matrix(value)


FUNCTIONS = {
    "sin": sp.sin, "cos": sp.cos, "tan": sp.tan,
    "asin": sp.asin, "acos": sp.acos, "atan": sp.atan,
    "sinh": sp.sinh, "cosh": sp.cosh, "tanh": sp.tanh,
    "sqrt": sp.sqrt, "exp": sp.exp, "log": sp.log,
    "Abs": sp.Abs, "Rational": sp.Rational, "Matrix": matrix,
    "Eq": sp.Eq, "And": sp.And, "Or": sp.Or, "Not": sp.Not,
    "Xor": sp.Xor, "Implies": sp.Implies, "Equivalent": sp.Equivalent,
}
CONSTANTS = {"pi": sp.pi, "E": sp.E, "I": sp.I, "oo": sp.oo,
             "True": sp.true, "False": sp.false}


def parse_expression(text):
    if not isinstance(text, str) or not text.strip() or len(text) > 1024:
        raise ValueError("Expression must contain 1 to 1024 characters")
    tree = ast.parse(text, mode="eval")
    if sum(1 for _ in ast.walk(tree)) > 160:
        raise ValueError("Expression is too large")

    def visit(node, depth=0):
        if depth > 24:
            raise ValueError("Expression nesting limit reached")
        child = lambda item: visit(item, depth + 1)
        if isinstance(node, ast.Constant):
            if isinstance(node.value, bool):
                return sp.true if node.value else sp.false
            if isinstance(node.value, int) and len(str(abs(node.value))) <= 100:
                return sp.Integer(node.value)
            if isinstance(node.value, float) and math.isfinite(node.value):
                return sp.Float(node.value)
            raise ValueError("Only finite numeric literals are allowed")
        if isinstance(node, ast.Name):
            if node.id in CONSTANTS:
                return CONSTANTS[node.id]
            if not node.id.isascii() or node.id.startswith("_") or len(node.id) > 32:
                raise ValueError("Invalid symbol name")
            return sp.Symbol(node.id)
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
                if right.is_number and (right.is_real is not True or abs(right) > 64):
                    raise ValueError("Numeric exponent limit is 64")
                return left ** right
            if isinstance(node.op, ast.BitAnd): return sp.And(left, right)
            if isinstance(node.op, ast.BitOr): return sp.Or(left, right)
            if isinstance(node.op, ast.BitXor): return sp.Xor(left, right)
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in FUNCTIONS:
                raise ValueError("Function is not permitted")
            if node.keywords or len(node.args) > 8:
                raise ValueError("Unsupported function arguments")
            return FUNCTIONS[node.func.id](*[child(arg) for arg in node.args])
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            operators = {ast.Eq: sp.Eq, ast.NotEq: sp.Ne, ast.Lt: sp.Lt,
                         ast.LtE: sp.Le, ast.Gt: sp.Gt, ast.GtE: sp.Ge}
            operator = operators.get(type(node.ops[0]))
            if operator:
                return operator(child(node.left), child(node.comparators[0]))
        raise ValueError("Unsupported expression syntax")

    return visit(tree.body)


def calculate(request):
    expression = parse_expression(request.get("expression"))
    name = request.get("variable", "x")
    if not isinstance(name, str) or not name.isascii() or not name.isidentifier() or name.startswith("_") or len(name) > 32:
        raise ValueError("Invalid variable")
    variable = sp.Symbol(name)
    operation = request.get("operation")
    if operation in {"Boolean simplify", "Satisfiable"}:
        if not isinstance(expression, sp.logic.boolalg.Boolean) or expression.has(Relational):
            raise ValueError("Boolean logic requires propositions, not arithmetic constraints")
    operations = {
        "Simplify": lambda: sp.simplify(expression),
        "Expand": lambda: sp.expand(expression),
        "Factor": lambda: sp.factor(expression),
        "Differentiate": lambda: sp.diff(expression, variable),
        "Integrate": lambda: sp.integrate(expression, variable),
        "Solve = 0": lambda: sp.solve(expression, variable),
        "Determinant": lambda: matrix(expression).det() if isinstance(expression, list) else expression.det(),
        "Inverse": lambda: matrix(expression).inv() if isinstance(expression, list) else expression.inv(),
        "Eigenvalues": lambda: matrix(expression).eigenvals() if isinstance(expression, list) else expression.eigenvals(),
        "Boolean simplify": lambda: sp.simplify_logic(expression),
        "Satisfiable": lambda: sp.satisfiable(expression),
    }
    if operation not in operations:
        raise ValueError("Unknown operation")
    result = str(operations[operation]())
    if operation == "Integrate":
        result += " + C"
    if len(result) > 16000:
        raise ValueError("Result exceeds the display budget")
    return {"ok": True, "result": result}


if __name__ == "__main__":
    try:
        raw = sys.stdin.buffer.read(8193)
        if len(raw) > 8192:
            raise ValueError("Request is too large")
        result = calculate(json.loads(raw))
    except Exception as error:
        result = {"ok": False, "error": str(error)[:300]}
    print(json.dumps(result))
