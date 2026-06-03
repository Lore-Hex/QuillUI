// CKiwiBridge.cpp — implements the pure-C ABI in CKiwiBridge.h on top of kiwi.
#include "CKiwiBridge.h"

#include "kiwi/kiwi.h"

#include <string>
#include <vector>

struct QLSolver {
    kiwi::Solver solver;
    std::vector<kiwi::Variable> vars;
};

static double ql_strength(int strength) {
    switch (strength) {
    case QL_REQUIRED: return kiwi::strength::required;
    case QL_STRONG:   return kiwi::strength::strong;
    case QL_MEDIUM:   return kiwi::strength::medium;
    default:          return kiwi::strength::weak;
    }
}

extern "C" {

QLSolver *ql_solver_new(void) { return new QLSolver(); }
void ql_solver_free(QLSolver *s) { delete s; }

int ql_solver_add_var(QLSolver *s, const char *name) {
    s->vars.emplace_back(name ? std::string(name) : std::string());
    return static_cast<int>(s->vars.size()) - 1;
}

int ql_solver_add_constraint(QLSolver *s, const int *ids, const double *coeffs,
                             int n, double constant, int op, int strength) {
    try {
        std::vector<kiwi::Term> terms;
        terms.reserve(n);
        for (int i = 0; i < n; ++i) {
            terms.emplace_back(s->vars.at(ids[i]), coeffs[i]);
        }
        kiwi::Expression expr(std::move(terms), constant);
        kiwi::RelationalOperator rop =
            op == QL_OP_LE ? kiwi::OP_LE : (op == QL_OP_GE ? kiwi::OP_GE : kiwi::OP_EQ);
        kiwi::Constraint c(expr, rop, ql_strength(strength));
        s->solver.addConstraint(c);
        return 0;
    } catch (...) {
        return 1;
    }
}

int ql_solver_add_edit_var(QLSolver *s, int id, int strength) {
    try {
        s->solver.addEditVariable(s->vars.at(id), ql_strength(strength));
        return 0;
    } catch (...) {
        return 1;
    }
}

int ql_solver_suggest(QLSolver *s, int id, double value) {
    try {
        s->solver.suggestValue(s->vars.at(id), value);
        return 0;
    } catch (...) {
        return 1;
    }
}

void ql_solver_update(QLSolver *s) { s->solver.updateVariables(); }

double ql_solver_value(QLSolver *s, int id) { return s->vars.at(id).value(); }

void ql_solver_reset(QLSolver *s) { s->solver.reset(); }

} // extern "C"
