// CKiwiBridge.h — pure-C ABI over the kiwi Cassowary solver (nucleic/kiwi, C++).
//
// This is the only public header of the CKiwi target, so Swift's Clang importer
// never sees kiwi's C++ headers (they live in the private Sources/CKiwi/kiwi/).
// QuillAutoLayout drives Auto Layout (NSLayoutConstraint) through these calls.
#ifndef QUILL_CKIWI_BRIDGE_H
#define QUILL_CKIWI_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QLSolver QLSolver;

// Relational operators for a constraint: sum(coeff[i]*var[i]) + constant <op> 0
enum { QL_OP_LE = 0, QL_OP_GE = 1, QL_OP_EQ = 2 };
// Strengths (kiwi): required is mandatory; the rest are soft (descending).
enum { QL_REQUIRED = 0, QL_STRONG = 1, QL_MEDIUM = 2, QL_WEAK = 3 };

QLSolver *ql_solver_new(void);
void ql_solver_free(QLSolver *s);

// Create a solver variable; returns its integer id (>= 0).
int ql_solver_add_var(QLSolver *s, const char *name);

// Add constraint  sum_{i<n}(coeffs[i]*var[ids[i]]) + constant  <op>  0.
// Returns 0 on success, nonzero if kiwi rejected it (unsatisfiable/duplicate).
int ql_solver_add_constraint(QLSolver *s, const int *ids, const double *coeffs,
                             int n, double constant, int op, int strength);

// Edit variables let you suggest a value (e.g. a container's measured size).
// strength must be soft (not QL_REQUIRED). Returns 0 on success.
int ql_solver_add_edit_var(QLSolver *s, int id, int strength);
int ql_solver_suggest(QLSolver *s, int id, double value);

void ql_solver_update(QLSolver *s);      // recompute variable values
double ql_solver_value(QLSolver *s, int id);
void ql_solver_reset(QLSolver *s);       // clear all constraints/edits

#ifdef __cplusplus
}
#endif

#endif // QUILL_CKIWI_BRIDGE_H
