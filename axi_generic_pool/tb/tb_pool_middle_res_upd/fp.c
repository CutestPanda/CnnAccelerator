#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

#include "svdpi.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

unsigned int encode_fp16(double d) {
	float value = (float)d;
	uint32_t* f_ptr = (uint32_t*)(&value);
	uint32_t f_int = *f_ptr;
	
    // 提取float的各个部分（IEEE 754单精度）
    uint32_t sign = (f_int >> 31) & 0x1;           // 符号位
    int32_t exp = ((f_int >> 23) & 0xFF) - 127;    // 指数（去除127偏移）
    uint32_t mant = f_int & 0x7FFFFF;              // 尾数（23位）
    
    // 处理特殊情况：NaN和无穷大
    if (exp == 128) { // 指数全为1
        if (mant != 0) { // 尾数非零 -> NaN
            return 0x7FFF; // FP16 NaN
        } else { // 尾数为零 -> 无穷大
            return (sign << 15) | 0x7C00; // FP16无穷大
        }
    }
    
    // 处理零和次正规数（指数 < -14）
    if (exp < -14) {
        if (exp < -24) { // 太小，直接下溢为零
            return sign << 15;
        }
        
        // 转换为次正规数（denormal）
        int shift = -(exp + 14);
		mant |= 0x800000; // 添加隐含的1位
        mant >>= shift;
        
        // 最近偶数舍入
        uint32_t round_bit = (mant >> 12) & 0x1;     // mant[12]
        uint32_t sticky_bits = mant & 0xFFF;         // mant[11:0]
        
        mant >>= 13; // 保留10位尾数
        
        if (round_bit && (sticky_bits || (mant & 0x1))) {
            mant++;
            if (mant & 0x400) { // 进位到正规数范围
                mant = 0;
                exp = -14;
            }
        }
		
		if(exp == -14){
			return (sign << 15) | (0x0001 << 10);
		}else{
			return (sign << 15) | mant;
		}
    }
    
    // 处理溢出（指数 > 15）
    if (exp > 15) { // 超过FP16最大范围
        return (sign << 15) | 0x7C00; // 返回无穷大
    }
    
    // 正常范围转换
    exp += 15; // 应用FP16的指数偏移（从-127偏移到-15偏移）
	
	// 最近偶数舍入
    uint32_t round_bit = (mant >> 12) & 0x1;    // mant[12]
    uint32_t sticky_bits = mant & 0xFFF;        // mant[11:0]
    
    mant >>= 13; // 保留10位尾数
    
    if (round_bit && (sticky_bits || (mant & 0x1))) {
        mant++;
        if (mant & 0x400) { // 检查是否进位到指数
            mant = 0;
            exp++;
            if (exp > 30) { // 溢出到无穷大
                return (sign << 15) | 0x7C00;
            }
        }
    }
    
    // 组装最终FP16值
    return (sign << 15) | ((exp & 0x1F) << 10) | (mant & 0x3FF);
}

unsigned int encode_fp32(double d) {
	float f = (float)d;
	
	uint32_t* f_ptr = (uint32_t*)(&f);
	uint32_t f_int = *f_ptr;
	
	return f_int;
}

double decode_fp16(int unsigned fp16) {
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
	
	return (double)f;
}

double decode_fp32(int unsigned fp32) {
	float f;
	
	uint32_t* f_ptr = (uint32_t*)(&f);
	
	*f_ptr = fp32;
	
	return (double)f;
}
