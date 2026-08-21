/* Minimal compiled source, present so that R runs make over src/ and therefore
   parses src/Makevars. Nothing here is instrumented: compiling is not
   executing, and this function is never called.

   Registering it through useDynLib in NAMESPACE and an R_init_foo() routine
   would add a genuine load-time site, since R calls R_init_<pkg> when the
   shared object is loaded. Deliberately left out for now. */

#include <R.h>
#include <Rinternals.h>

SEXP foo_noop(void) {
  return R_NilValue;
}
