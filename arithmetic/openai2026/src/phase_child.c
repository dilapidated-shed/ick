#include "numerical.h"
#include "exact_internal.h"

#define TRY(operation) do { status=(operation); if (status!=EXACT_OK) goto done; } while (0)
static exact_dyadic *part(exact_gaussian *value,unsigned component) { return component ? &value->imaginary : &value->real; }
static void phase(exact_gaussian *value,unsigned quarter) {
  for (unsigned index=0;index<(quarter&3);++index) {
    exact_dyadic temporary=value->real; value->real=value->imaginary; value->imaginary=temporary; value->real.sign=-value->real.sign;
  }
}
exact_status numerical_C_child(exact_gaussian output[2],const exact_gaussian input[2],int inverse) {
  if (!output || !input || (inverse!=0 && inverse!=1)
      || (output!=input && exact_overlap(output,2*sizeof(*output),input,2*sizeof(*input)))) return EXACT_INVALID;
  size_t capacity=0;
  for (unsigned index=0;index<8;++index) {
    const exact_dyadic *value=index<4 ? part((exact_gaussian *)&input[index/2],index%2)
                                      : part(&output[(index-4)/2],index%2);
    if (!exact_valid(value)) return EXACT_INVALID;
    if (value->capacity>capacity) capacity=value->capacity;
    for (unsigned previous=0;previous<index;++previous) {
      const exact_dyadic *other=previous<4 ? part((exact_gaussian *)&input[previous/2],previous%2)
                                          : part(&output[(previous-4)/2],previous%2);
      if (exact_alias_invalid(value,other)) return EXACT_INVALID;
    }
  }
  if (capacity>128) return EXACT_CAPACITY;
  exact_gaussian controls[2]={0},result[2]={0},sum={0},difference={0}; exact_status status=EXACT_OK;
  for (unsigned index=0;index<2;++index) for (unsigned component=0;component<2;++component) {
    TRY(exact_init(part(&controls[index],component),capacity)); TRY(exact_init(part(&result[index],component),capacity));
    TRY(exact_copy(part(&controls[index],component),part((exact_gaussian *)&input[index],component)));
  }
  TRY(exact_init(&sum.real,capacity)); TRY(exact_init(&sum.imaginary,capacity));
  TRY(exact_init(&difference.real,capacity)); TRY(exact_init(&difference.imaginary,capacity));
  if (inverse) phase(&controls[1],2); /* rightmost Z */
  TRY(exact_add(&sum.real,&controls[0].real,&controls[1].real));
  TRY(exact_add(&sum.imaginary,&controls[0].imaginary,&controls[1].imaginary));
  TRY(exact_subtract(&difference.real,&controls[0].real,&controls[1].real));
  TRY(exact_subtract(&difference.imaginary,&controls[0].imaginary,&controls[1].imaginary));
  phase(&difference,1);
  TRY(exact_add(&result[0].real,&sum.real,&difference.real)); TRY(exact_half(&result[0].real,&result[0].real));
  TRY(exact_add(&result[0].imaginary,&sum.imaginary,&difference.imaginary)); TRY(exact_half(&result[0].imaginary,&result[0].imaginary));
  TRY(exact_subtract(&result[1].real,&sum.real,&difference.real)); TRY(exact_half(&result[1].real,&result[1].real));
  TRY(exact_subtract(&result[1].imaginary,&sum.imaginary,&difference.imaginary)); TRY(exact_half(&result[1].imaginary,&result[1].imaginary));
  if (inverse) {
    phase(&result[1],2); /* leftmost Z */
#ifdef MUTANT_INVERSE_PHASE
    phase(&result[0],1); phase(&result[1],1);
#else
    phase(&result[0],3); phase(&result[1],3); /* -i */
#endif
  }
  for (unsigned index=0;index<2;++index) for (unsigned component=0;component<2;++component)
    if (part(&result[index],component)->length>part(&output[index],component)->capacity) { status=EXACT_CAPACITY; goto done; }
  for (unsigned index=0;index<2;++index) for (unsigned component=0;component<2;++component)
    TRY(exact_copy(part(&output[index],component),part(&result[index],component)));
done:
  for (unsigned index=0;index<2;++index) { exact_clear(&controls[index].real); exact_clear(&controls[index].imaginary); exact_clear(&result[index].real); exact_clear(&result[index].imaginary); }
  exact_clear(&sum.real); exact_clear(&sum.imaginary); exact_clear(&difference.real); exact_clear(&difference.imaginary); return status;
}
