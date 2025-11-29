#include "sd_card_fatfs.h"
#include "axi_generic_conv.h"

#include "xparameters.h"

#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define IN_FMAP_FILENAME "in_fmap.bin" // 输入特征图文件名
#define OUT_FMAP_FILENAME "out_fmap.bin" // 输出特征图文件名
#define KWGT_FILENAME "kernal.bin" // 卷积核权重文件名

#define IN_FMAP_LEN 8125 // 输入特征图数据总量
#define KWGT_LEN 1053 // 卷积核权重数据总量
#define OUT_FMAP_LEN 5625 // 输出特征图数据总量

#define OUT_FMAP_SUB_ROW_N 50 // 输出特征图子表面行总数

#define IN_DATA_LEN 2 // 输入特征图或卷积核的数据大小
#define OUT_DATA_LEN 4 // 输出特征图的数据大小

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static FATFS fatfs; // FAT32文件系统
static FIL file_handler; // 文件描述符

static AxiGnrConvHandler axi_generic_conv; // 通用卷积处理单元

static uint16_t in_fmap[IN_FMAP_LEN]; // 输入特征图(数组)
static uint16_t kwgt[KWGT_LEN]; // 卷积核权重(数组)
static float out_fmap[OUT_FMAP_LEN]; // 输出特征图(数组)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 初始化SD卡文件系统
	if(init_sd_card_fatfs(&fatfs, 0)){
		return -1;
	}

	// 从SD卡读取输入特征图
	if(sd_card_fatfs_fopen(&file_handler, IN_FMAP_FILENAME, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)in_fmap, IN_FMAP_LEN * IN_DATA_LEN) != IN_FMAP_LEN * IN_DATA_LEN){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 从SD卡读取卷积核权重
	if(sd_card_fatfs_fopen(&file_handler, KWGT_FILENAME, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)kwgt, KWGT_LEN * IN_DATA_LEN) != KWGT_LEN * IN_DATA_LEN){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 初始化通用卷积处理单元
	if(axi_generic_conv_init(&axi_generic_conv, XPAR_AXI_GENERIC_CONV_0_BASEADDR)){
		return -1;
	}

	// 配置卷积层参数
	AxiGnrConvCfg conv_cfg;

	conv_cfg.ifmap_baseaddr = (uint8_t*)in_fmap;
	conv_cfg.ofmap_baseaddr = (uint8_t*)out_fmap;
	conv_cfg.kernal_wgt_baseaddr = (uint8_t*)kwgt;
	conv_cfg.group_n = 1;
	conv_cfg.max_wgtblk_w = 8;
	conv_cfg.cal_cfg.cal_fmt = CONV_FP16;
	conv_cfg.cal_cfg.cal_round_n = 1;
	conv_cfg.cal_cfg.conv_horizontal_stride = 1;
	conv_cfg.cal_cfg.conv_vertical_stride = 1;
	conv_cfg.fmap_cfg.external_padding_bottom = 1;
	conv_cfg.fmap_cfg.external_padding_left = 1;
	conv_cfg.fmap_cfg.external_padding_right = 1;
	conv_cfg.fmap_cfg.external_padding_top = 1;
	conv_cfg.fmap_cfg.inner_padding_left_right = 0;
	conv_cfg.fmap_cfg.inner_padding_top_bottom = 0;
	conv_cfg.fmap_cfg.ifmap_width = 25;
	conv_cfg.fmap_cfg.ifmap_height = 25;
	conv_cfg.fmap_cfg.ifmap_chn_n = 13;
	conv_cfg.fmap_cfg.ofmap_data_type = CONV_O_4_BYTE;
	conv_cfg.kernal_cfg.dilation_n = 0;
	conv_cfg.kernal_cfg.kernal_chn_n = 13;
	conv_cfg.kernal_cfg.kernal_n = 9;
	conv_cfg.kernal_cfg.kernal_shape = CONV_KRN_3x3;
	conv_cfg.buffer_cfg.fmbufbankn = 2;
	conv_cfg.buffer_cfg.fmbufcoln = CONV_COLN_32;
	conv_cfg.buffer_cfg.sfc_n_each_wgtblk = CONV_WGTBLK_SFC_N_8;

	if(axi_generic_conv_cfg(&axi_generic_conv, (const AxiGnrConvCfg*)(&conv_cfg))){
		return -1;
	}

	// 启动通用卷积处理单元
	if(axi_generic_conv_enable_cal_sub_sys(&axi_generic_conv)){
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
	while(axi_generic_conv_get_cmd_fns_n(&axi_generic_conv, Q_CMD_FNS_N_S2MM) < OUT_FMAP_SUB_ROW_N);

	// 获取性能监测计数器的值
	int pm_cnt = (int)axi_generic_conv_get_pm_cnt(&axi_generic_conv);
	printf("pm_cnt = %d\r\n", pm_cnt);

	// 除能计算子系统
	axi_generic_conv_disable_cal_sub_sys(&axi_generic_conv);
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

	// 向SD卡写入输出特征图
	if(sd_card_fatfs_fopen(&file_handler, OUT_FMAP_FILENAME, FA_WRITE | FA_CREATE_ALWAYS, 0)){
		return -1;
	}

	if(sd_card_fatfs_fwrite(&file_handler, (void*)out_fmap, OUT_FMAP_LEN * OUT_DATA_LEN) != OUT_FMAP_LEN * OUT_DATA_LEN){
		return -1;
	}

	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	while(1);
}
