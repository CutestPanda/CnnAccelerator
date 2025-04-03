#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

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
	
	frac >>= 13;
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

double get_fp32(int unsigned fp32) {
	float f;
	
	uint32_t* f_ptr = (uint32_t*)(&f);
	
	*f_ptr = fp32;
	
	return (double)f;
}

double get_fixed36_exp(long long int frac, int exp) {
	float f = ((float)frac) * powf(2.0f, exp - 50);
	
	return (double)f;
}
