#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "vpi_user.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

unsigned int get_fp16(int log_fid, double d) {
	float f = (float)d;
	
	uint32_t* f_ptr = (uint32_t*)(&f);
	uint32_t f_int = *f_ptr;
	
	uint16_t sign = (f_int & 0x80000000) ? 0x0001:0x0000;
	uint16_t exp = ((f_int & 0x7F800000) >> 23);
	uint32_t frac = f_int & 0x007FFFFF;
	
	uint16_t fp16 = 0x0000;
	
	fp16 |= (sign << 15);
	
	if(exp <= (127 - 15)) {
		exp = 0;
	}else if(exp >= (127 + 16)) {
		exp = 31;
	}else {
		exp = exp - 127 + 15;
	}
	fp16 |= (exp << 10);
	
	int8_t to_add_1;
	
	if(frac != 0x007FFFFF){
		to_add_1 = (frac & (1 << 12)) ? 0x01:0x00;
	}else{
		to_add_1 = 0;
	}
	
	frac >>= 13;
	if(to_add_1){
		frac++;
	}
	
	fp16 |= frac;
	
	return (unsigned int)fp16;
}

void print_fp16(int log_fid, int unsigned fp16) {
	float f;
	
	uint32_t* f_ptr = (uint32_t*)(&f);
	uint32_t f_int = 0x00000000;
	
	uint16_t sign = (fp16 & 0x00008000) ? 0x0001:0x0000;
	uint16_t exp = ((fp16 & 0x00007C00) >> 10);
	uint16_t frac = fp16 & 0x000003FF;
	
	f_int |= (((uint32_t)sign) << 31);
	
	exp = exp - 15 + 127;
	f_int |= (((uint32_t)exp) << 23);
	
	f_int |= (((uint32_t)frac) << 13);
	
	*f_ptr = f_int;
	
	vpi_mcd_printf(log_fid, "fp16 = %f\n", f);
}
