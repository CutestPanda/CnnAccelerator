/**
通用卷积处理单元IP配置参数:
	parameter integer BN_SUPPORTED = 1; // 是否支持批归一化处理
	parameter integer LEAKY_RELU_SUPPORTED = 1; // 是否支持Leaky-Relu激活
	parameter integer INT8_SUPPORTED = 0; // 是否支持INT8
	parameter integer INT16_SUPPORTED = 0; // 是否支持INT16
	parameter integer FP16_SUPPORTED = 1; // 是否支持FP16
	parameter integer LARGE_V_STRD_SUPPORTED = 1; // 是否支持>1的卷积垂直步长
	parameter integer LARGE_H_STRD_SUPPORTED = 1; // 是否支持>1的卷积水平步长
	parameter integer GRP_CONV_SUPPORTED = 0; // 是否支持组卷积
	parameter integer EXT_PADDING_SUPPORTED = 1; // 是否支持外填充
	parameter integer INNER_PADDING_SUPPORTED = 0; // 是否支持内填充
	parameter integer KERNAL_DILATION_SUPPORTED = 0; // 是否支持卷积核膨胀
	parameter integer EN_PERF_MON = 1; // 是否支持性能监测
	parameter integer ACCELERATOR_ID = 0; // 加速器ID(0~3)
	
	parameter integer ATOMIC_K = 8; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 8; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64; // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64; // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 4; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
**/

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "sd_card_fatfs.h"
#include "axi_generic_conv.h"

#include "xparameters.h"
#include "xil_cache.h"

#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// #define TO_FLUSH_DCACHE // 是否需要刷新DCache

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int test_conv_layer(
	char* in_fmap_filename, int in_fmap_len,
	char* kernal_filename, int kernal_len,
	char* bn_param_filename, void* bn_param_buf, int bn_param_n,
	char* out_fmap_filename, int out_fmap_len, uint32_t out_fmap_sfc_row_n,
	const AxiGnrConvCfg* conv_cfg
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static FATFS fatfs; // FAT32文件系统
static FIL file_handler; // 文件描述符

static AxiGnrConvHandler axi_generic_conv; // 通用卷积处理单元

// 输入特征图(数组)
static uint16_t in_fmap_0[640 * 640 * 3];
static uint16_t in_fmap_1[320 * 320 * 16];

// 卷积核权重(数组)
static uint16_t kwgt_0[3 * 3 * 3 * 16];
static uint16_t kwgt_1[3 * 3 * 16 * 32];

// 输出特征图(数组)
static float out_fmap_0[640 * 640 * 16];
static float out_fmap_1[320 * 320 * 32];

// BN参数(数组)
static BNParam bn_params_0[16];
static BNParam bn_params_1[32];

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 初始化SD卡文件系统
	if(init_sd_card_fatfs(&fatfs, 0)){
		return -1;
	}

	// 初始化通用卷积处理单元
	if(axi_generic_conv_init(&axi_generic_conv, XPAR_AXI_GENERIC_CONV_0_BASEADDR)){
		return -1;
	}

	AxiGnrConvCfg conv_cfg;

	conv_cfg.ifmap_baseaddr = (uint8_t*)in_fmap_0;
	conv_cfg.ofmap_baseaddr = (uint8_t*)out_fmap_0;
	conv_cfg.kernal_wgt_baseaddr = (uint8_t*)kwgt_0;
	conv_cfg.group_n = 1;
	conv_cfg.max_wgtblk_w = 16;
	conv_cfg.cal_cfg.cal_fmt = CONV_FP16;
	conv_cfg.cal_cfg.cal_round_n = 2;
	conv_cfg.cal_cfg.conv_horizontal_stride = 1;
	conv_cfg.cal_cfg.conv_vertical_stride = 1;
	conv_cfg.fmap_cfg.external_padding_bottom = 1;
	conv_cfg.fmap_cfg.external_padding_left = 1;
	conv_cfg.fmap_cfg.external_padding_right = 1;
	conv_cfg.fmap_cfg.external_padding_top = 1;
	conv_cfg.fmap_cfg.inner_padding_left_right = 0;
	conv_cfg.fmap_cfg.inner_padding_top_bottom = 0;
	conv_cfg.fmap_cfg.ifmap_width = 640;
	conv_cfg.fmap_cfg.ifmap_height = 640;
	conv_cfg.fmap_cfg.ifmap_chn_n = 3;
	conv_cfg.fmap_cfg.ofmap_data_type = CONV_O_4_BYTE;
	conv_cfg.kernal_cfg.dilation_n = 0;
	conv_cfg.kernal_cfg.kernal_chn_n = 3;
	conv_cfg.kernal_cfg.kernal_n = 16;
	conv_cfg.kernal_cfg.kernal_shape = CONV_KRN_3x3;
	conv_cfg.buffer_cfg.fmbufbankn = 14;
	conv_cfg.buffer_cfg.fmbufcoln = CONV_COLN_1024;
	conv_cfg.buffer_cfg.sfc_n_each_wgtblk = CONV_WGTBLK_SFC_N_16;
	conv_cfg.bn_act_cfg.use_bn_unit = 1;
	conv_cfg.bn_act_cfg.use_act_unit = 0;
	conv_cfg.bn_act_cfg.bn_is_a_eq_1 = 1;
	conv_cfg.bn_act_cfg.bn_is_b_eq_0 = 0;
	conv_cfg.bn_act_cfg.leaky_relu_param_alpha = 0.01f;

	if(test_conv_layer(
		"in_fmap_0.bin", 640 * 640 * 3 * 2,
		"kernal_0.bin", 3 * 3 * 3 * 16 * 2,
		"bn_0.bin", (void*)bn_params_0, 16,
		"out_fmap_0.bin", 640 * 640 * 16 * 4, 640 * 2,
		(const AxiGnrConvCfg*)(&conv_cfg)
	)){
		return -1;
	}

	conv_cfg.ifmap_baseaddr = (uint8_t*)in_fmap_1;
	conv_cfg.ofmap_baseaddr = (uint8_t*)out_fmap_1;
	conv_cfg.kernal_wgt_baseaddr = (uint8_t*)kwgt_1;
	conv_cfg.group_n = 1;
	conv_cfg.max_wgtblk_w = 16;
	conv_cfg.cal_cfg.cal_fmt = CONV_FP16;
	conv_cfg.cal_cfg.cal_round_n = 2;
	conv_cfg.cal_cfg.conv_horizontal_stride = 1;
	conv_cfg.cal_cfg.conv_vertical_stride = 1;
	conv_cfg.fmap_cfg.external_padding_bottom = 1;
	conv_cfg.fmap_cfg.external_padding_left = 1;
	conv_cfg.fmap_cfg.external_padding_right = 1;
	conv_cfg.fmap_cfg.external_padding_top = 1;
	conv_cfg.fmap_cfg.inner_padding_left_right = 0;
	conv_cfg.fmap_cfg.inner_padding_top_bottom = 0;
	conv_cfg.fmap_cfg.ifmap_width = 320;
	conv_cfg.fmap_cfg.ifmap_height = 320;
	conv_cfg.fmap_cfg.ifmap_chn_n = 16;
	conv_cfg.fmap_cfg.ofmap_data_type = CONV_O_4_BYTE;
	conv_cfg.kernal_cfg.dilation_n = 0;
	conv_cfg.kernal_cfg.kernal_chn_n = 16;
	conv_cfg.kernal_cfg.kernal_n = 32;
	conv_cfg.kernal_cfg.kernal_shape = CONV_KRN_3x3;
	conv_cfg.buffer_cfg.fmbufbankn = 14;
	conv_cfg.buffer_cfg.fmbufcoln = CONV_COLN_512;
	conv_cfg.buffer_cfg.sfc_n_each_wgtblk = CONV_WGTBLK_SFC_N_16;
	conv_cfg.bn_act_cfg.use_bn_unit = 1;
	conv_cfg.bn_act_cfg.use_act_unit = 0;
	conv_cfg.bn_act_cfg.bn_is_a_eq_1 = 1;
	conv_cfg.bn_act_cfg.bn_is_b_eq_0 = 0;
	conv_cfg.bn_act_cfg.leaky_relu_param_alpha = 0.01f;

	if(test_conv_layer(
		"in_fmap_1.bin", 320 * 320 * 16 * 2,
		"kernal_1.bin", 3 * 3 * 16 * 32 * 2,
		"bn_1.bin", (void*)bn_params_1, 32,
		"out_fmap_1.bin", 320 * 320 * 32 * 4, 320 * 4,
		(const AxiGnrConvCfg*)(&conv_cfg)
	)){
		return -1;
	}

	while(1);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int test_conv_layer(
	char* in_fmap_filename, int in_fmap_len,
	char* kernal_filename, int kernal_len,
	char* bn_param_filename, void* bn_param_buf, int bn_param_n,
	char* out_fmap_filename, int out_fmap_len, uint32_t out_fmap_sfc_row_n,
	const AxiGnrConvCfg* conv_cfg
){
	// 从SD卡读取输入特征图
	if(sd_card_fatfs_fopen(&file_handler, in_fmap_filename, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)conv_cfg->ifmap_baseaddr, in_fmap_len) != in_fmap_len){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 从SD卡读取卷积核权重
	if(sd_card_fatfs_fopen(&file_handler, kernal_filename, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)conv_cfg->kernal_wgt_baseaddr, kernal_len) != kernal_len){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 从SD卡读取BN参数
	if(sd_card_fatfs_fopen(&file_handler, bn_param_filename, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, bn_param_buf, bn_param_n * 2 * 4) != bn_param_n * 2 * 4){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 配置卷积层参数
	if(axi_generic_conv_cfg(&axi_generic_conv, conv_cfg)){
		return -1;
	}

	// 写BN参数
	axi_generic_conv_wr_bn_param_mem(&axi_generic_conv, (BNParam*)bn_param_buf, (uint32_t)bn_param_n);

#ifdef TO_FLUSH_DCACHE
	// 刷新DCache
	Xil_DCacheFlushRange((INTPTR)conv_cfg->ifmap_baseaddr, in_fmap_len);
	Xil_DCacheFlushRange((INTPTR)conv_cfg->kernal_wgt_baseaddr, kernal_len);
#endif

	// 启动通用卷积处理单元
	if(axi_generic_conv_enable_cal_sub_sys(&axi_generic_conv)){
		return -1;
	}

	if(axi_generic_conv_enable_bn_act_proc(&axi_generic_conv)){
		return -1;
	}

	if(axi_generic_conv_start(&axi_generic_conv)){
		return -1;
	}

	// 使能性能监测计数器
	if(axi_generic_conv_enable_pm_cnt(&axi_generic_conv)){
		return -1;
	}

	// 等待通用卷积处理单元的数据输出完成
	while(axi_generic_conv_get_cmd_fns_n(&axi_generic_conv, Q_CMD_FNS_N_S2MM) < out_fmap_sfc_row_n);

	// 获取性能监测计数器的值
	int pm_cnt = (int)axi_generic_conv_get_pm_cnt(&axi_generic_conv);
	printf("pm_cnt = %d\r\n", pm_cnt);

	// 除能计算子系统
	axi_generic_conv_disable_cal_sub_sys(&axi_generic_conv);
	// 除能批归一化与激活处理单元
	axi_generic_conv_disable_bn_act_proc(&axi_generic_conv);
	// 除能性能监测计数器
	axi_generic_conv_disable_pm_cnt(&axi_generic_conv);

	// 清除DMA命令完成数
	if(axi_generic_conv_clr_cmd_fns_n(&axi_generic_conv, C_ALL)){
		return -1;
	}
	// 清除性能监测计数器
	if(axi_generic_conv_clr_pm_cnt(&axi_generic_conv)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	// 刷新DCache
	Xil_DCacheFlushRange((INTPTR)conv_cfg->ofmap_baseaddr, out_fmap_len);
#endif

	// 向SD卡写入输出特征图
	if(sd_card_fatfs_fopen(&file_handler, out_fmap_filename, FA_WRITE | FA_CREATE_ALWAYS, 0)){
		return -1;
	}

	if(sd_card_fatfs_fwrite(&file_handler, (void*)conv_cfg->ofmap_baseaddr, out_fmap_len) != out_fmap_len){
		return -1;
	}

	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	return 0;
}
