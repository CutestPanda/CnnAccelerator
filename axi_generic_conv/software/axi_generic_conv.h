/************************************************************************************************************************
通用卷积处理单元驱动(接口头文件)
@brief  提供了通用卷积处理单元的初始化、控制、状态获取、配置等API
@date   2025/11/29
@author 陈家耀
@eidt   2025.11.29 1.00 创建了第1个正式版本
        2025.11.29 1.01 将特征图缓存可缓存行数(fmbufrown)限制到最大可缓存行数(max_fmbuf_row_n)
        2025.12.05 1.10 增加批归一化处理
        2025.12.05 1.11 增加2个加速器属性(BN与激活并行数, 最大的卷积核个数), 增加写BN参数存储器的函数
        2025.12.09 1.12 增加配置加速器时对中间结果缓存可缓存行数的检查
        2025.12.12 1.13 修改对"分配给特征图缓存的Bank数"的合法性判断
        2025.12.20 1.20 修改批归一化与激活配置, 增加Leaky-Relu激活配置
        2025.12.22 1.21 增加性能监测计数器组(运行周期数, 0号MM2S通道传输字节数, 1号MM2S通道传输字节数, S2MM通道传输字节数)
        2025.12.22 1.22 增加性能监测计数器组(已计算的特征图表面数)
************************************************************************************************************************/

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 枚举类型: DMA命令完成数查询类别
typedef enum{
	Q_CMD_FNS_N_MM2S_0,
	Q_CMD_FNS_N_MM2S_1,
	Q_CMD_FNS_N_S2MM
}AxiGnrConvCmdFnsNQueryType;

// 枚举类型: DMA命令完成数(计数器)清除类别
typedef enum{
	C_CMD_FNS_N_MM2S_0,
	C_CMD_FNS_N_MM2S_1,
	C_CMD_FNS_N_S2MM,
	C_ALL
}AxiGnrConvCmdFnsNClrType;

// 枚举类型: 运算数据格式
typedef enum{
	CONV_INT8 = 0,
	CONV_INT16 = 1,
	CONV_FP16 = 2
}AxiGnrConvCalFmt;

// 枚举类型: 输出特征图数据格式
typedef enum{
	CONV_O_1_BYTE = 0,
	CONV_O_2_BYTE = 1,
	CONV_O_4_BYTE = 2
}AxiGnrConvOfmapDataType;

// 枚举类型: 卷积核形状
typedef enum{
	CONV_KRN_1x1 = 0,
	CONV_KRN_3x3 = 1,
	CONV_KRN_5x5 = 2,
	CONV_KRN_7x7 = 3,
	CONV_KRN_9x9 = 4,
	CONV_KRN_11x11 = 5
}AxiGnrConvKernalShape;

// 枚举类型: 特征图缓存表面行长度
typedef enum{
	CONV_COLN_4 = 0b0000,
	CONV_COLN_8 = 0b0001,
	CONV_COLN_16 = 0b0010,
	CONV_COLN_32 = 0b0011,
	CONV_COLN_64 = 0b0100,
	CONV_COLN_128 = 0b0101,
	CONV_COLN_256 = 0b0110,
	CONV_COLN_512 = 0b0111,
	CONV_COLN_1024 = 0b1000,
	CONV_COLN_2048 = 0b1001,
	CONV_COLN_4096 = 0b1010
}AxiGnrConvFmbufColnType;

// 枚举类型: 卷积核缓存权重块宽度
typedef enum{
	CONV_WGTBLK_SFC_N_1 = 0b000,
	CONV_WGTBLK_SFC_N_2 = 0b001,
	CONV_WGTBLK_SFC_N_4 = 0b010,
	CONV_WGTBLK_SFC_N_8 = 0b011,
	CONV_WGTBLK_SFC_N_16 = 0b100,
	CONV_WGTBLK_SFC_N_32 = 0b101,
	CONV_WGTBLK_SFC_N_64 = 0b110,
	CONV_WGTBLK_SFC_N_128 = 0b111
}AxiGnrConvWgtblkSfcNType;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 结构体: 加速器属性
typedef struct{
	char version[9]; // 版本号
	char accelerator_type[7]; // 加速器类型
	uint8_t accelerator_id; // 加速器ID

	uint8_t bn_supported; // 是否支持批归一化处理
	uint8_t leaky_relu_supported; // 是否支持Leaky-Relu激活
	uint8_t int8_supported; // 是否支持INT8运算数据格式
	uint8_t int16_supported; // 是否支持INT16运算数据格式
	uint8_t fp16_supported; // 是否支持FP16运算数据格式
	uint8_t large_v_stride_supported; // 是否支持>1的卷积垂直步长
	uint8_t large_h_stride_supported; // 是否支持>1的卷积水平步长
	uint8_t group_conv_supported; // 是否支持组卷积
	uint8_t ext_padding_supported; // 是否支持外填充
	uint8_t inner_padding_supported; // 是否支持内填充
	uint8_t kernal_dilation_supported; // 是否支持卷积核膨胀
	uint8_t performance_monitor_supported; // 是否支持性能监测

	uint8_t atomic_k; // 核并行数
	uint8_t atomic_c; // 通道并行数
	uint8_t bn_act_prl_n; // BN与激活并行数
	uint8_t max_cal_round_n; // 最大的计算轮次

	uint16_t mm2s_stream_data_width; // MM2S通道DMA数据流的位宽
	uint16_t s2mm_stream_data_width; // S2MM通道DMA数据流的位宽

	uint16_t phy_buf_bank_n; // 物理缓存BANK数
	uint16_t phy_buf_bank_depth; // 物理缓存BANK深度
	uint16_t max_fmbuf_row_n; // 特征图缓存最大表面行数
	uint16_t max_kernal_n; // 最大的卷积核个数
	uint8_t mid_res_buf_bank_n; // 中间结果缓存BANK数
	uint16_t mid_res_buf_bank_depth; // 中间结果缓存BANK深度
}AxiGnrConvProp;

// 结构体: 寄存器域(属性)
typedef struct{
	uint32_t version;
	uint32_t acc_name;
	uint32_t info0;
	uint32_t info1;
	uint32_t info2;
	uint32_t info3;
	uint32_t info4;
}AxiGnrConvRegRgnProp;

// 结构体: 寄存器域(控制)
typedef struct{
	uint32_t ctrl0;
}AxiGnrConvRegRgnCtrl;

// 结构体: 寄存器域(状态)
typedef struct{
	uint32_t sts0;
	uint32_t sts1;
	uint32_t sts2;
	uint32_t sts3;
	uint32_t sts4;
	uint32_t sts5;
	uint32_t sts6;
	uint32_t sts7;
	uint32_t sts8;
}AxiGnrConvRegRgnSts;

// 结构体: 寄存器域(计算配置)
typedef struct{
	uint32_t cal_cfg;
}AxiGnrConvRegRgnCalCfg;

// 结构体: 寄存器域(组卷积模式配置)
typedef struct{
	uint32_t grp_conv0;
	uint32_t grp_conv1;
}AxiGnrConvRegRgnGrpConvCfg;

// 结构体: 寄存器域(特征图配置)
typedef struct{
	uint32_t fmap_cfg0;
	uint32_t fmap_cfg1;
	uint32_t fmap_cfg2;
	uint32_t fmap_cfg3;
	uint32_t fmap_cfg4;
	uint32_t fmap_cfg5;
}AxiGnrConvRegRgnFmapCfg;

// 结构体: 寄存器域(卷积核配置)
typedef struct{
	uint32_t krn_cfg0;
	uint32_t krn_cfg1;
	uint32_t krn_cfg2;
	uint32_t krn_cfg3;
}AxiGnrConvRegRgnKrnCfg;

// 结构体: 寄存器域(缓存配置)
typedef struct{
	uint32_t buf_cfg0;
	uint32_t buf_cfg1;
	uint32_t buf_cfg2;
	uint32_t buf_cfg3;
}AxiGnrConvRegRgnBufCfg;

// 结构体: 寄存器域(批归一化与激活配置)
typedef struct{
	uint32_t bn_cfg;
	uint32_t act_cfg0;
	uint32_t act_cfg1;
}AxiGnrConvRegRgnBNActCfg;

// 结构体: 子配置参数(计算)
typedef struct{
	AxiGnrConvCalFmt cal_fmt; // 运算数据格式
	uint8_t conv_vertical_stride; // 卷积垂直步长
	uint8_t conv_horizontal_stride; // 卷积水平步长
	uint8_t cal_round_n; // 计算轮次
}AxiGnrConvCalCfg;

// 结构体: 子配置参数(特征图)
typedef struct{
	uint16_t ifmap_width; // 输入特征图宽度
	uint16_t ifmap_height; // 输入特征图高度
	uint16_t ifmap_chn_n; // 输入特征图通道数
	uint8_t external_padding_left; // 左部外填充数
	uint8_t external_padding_right; // 右部外填充数
	uint8_t external_padding_top; // 上部外填充数
	uint8_t external_padding_bottom; // 下部外填充数
	uint8_t inner_padding_left_right; // 左右内填充数
	uint8_t inner_padding_top_bottom; // 上下内填充数
	AxiGnrConvOfmapDataType ofmap_data_type; // 输出特征图数据类型
}AxiGnrConvFmapCfg;

// 结构体: 子配置参数(卷积核)
typedef struct{
	AxiGnrConvKernalShape kernal_shape; // 卷积核形状
	uint8_t dilation_n; // 卷积核膨胀量
	uint16_t kernal_chn_n; // 卷积核通道数
	uint16_t kernal_n; // 卷积核个数
}AxiGnrConvKernalCfg;

// 结构体: 子配置参数(缓存)
typedef struct{
	uint16_t fmbufbankn; // 分配给特征图缓存的Bank数
	AxiGnrConvFmbufColnType fmbufcoln; // 特征图缓存每个表面行的表面个数类型
	AxiGnrConvWgtblkSfcNType sfc_n_each_wgtblk; // 卷积核缓存每个权重块的表面个数的类型
}AxiGnrConvBufferCfg;

// 结构体: 子配置参数(BN与激活)
typedef struct{
	uint8_t use_bn_unit; // 启用BN单元
	uint8_t use_act_unit; // 启用激活单元
	uint8_t bn_fixed_point_quat_accrc; // (批归一化操作数A)定点数量化精度
	uint8_t bn_is_a_eq_1; // 批归一化参数A的实际值是否为1
	uint8_t bn_is_b_eq_0; // 批归一化参数B的实际值是否为0
	uint8_t leaky_relu_point_quat_accrc; // (泄露Relu激活参数)定点数量化精度
	float leaky_relu_param_alpha; // 泄露Relu激活参数
}AxiGnrConvBNActCfg;

// 结构体: 配置参数
typedef struct{
	AxiGnrConvCalCfg cal_cfg; // 子配置参数(计算)
	AxiGnrConvFmapCfg fmap_cfg; // 子配置参数(特征图)
	AxiGnrConvKernalCfg kernal_cfg; // 子配置参数(卷积核)
	AxiGnrConvBufferCfg buffer_cfg; // 子配置参数(缓存)
	AxiGnrConvBNActCfg bn_act_cfg; // 子配置参数(BN与激活)

	uint8_t* ifmap_baseaddr; // 输入特征图基地址
	uint8_t* ofmap_baseaddr; // 输出特征图基地址
	uint8_t* kernal_wgt_baseaddr; // 卷积核权重基地址

	uint16_t group_n; // 分组数

	uint8_t max_wgtblk_w; // 权重块最大宽度
}AxiGnrConvCfg;

// 结构体: BN参数
typedef struct{
	float param_a;
	float param_b;
}BNParam;

// 结构体: 性能监测状态
typedef struct{
	uint32_t cycle_n; // 运行周期数
	uint32_t mm2s_chn0_tsf_n; // 0号MM2S通道传输字节数
	uint32_t mm2s_chn1_tsf_n; // 1号MM2S通道传输字节数
	uint32_t s2mm_tsf_n; // S2MM通道传输字节数
	uint32_t ftm_sfc_cal_n; // 已计算的特征图表面数
}AxiGnrConvPerfMonsts;

// 结构体: 通用卷积处理单元
typedef struct{
	uint32_t* reg_base_ptr; // 寄存器区基地址

	// 寄存器域
	AxiGnrConvRegRgnProp* reg_region_prop; // 寄存器域(属性)
	AxiGnrConvRegRgnCtrl* reg_region_ctrl; // 寄存器域(控制)
	AxiGnrConvRegRgnSts* reg_region_sts; // 寄存器域(状态)
	AxiGnrConvRegRgnCalCfg* reg_region_cal_cfg; // 寄存器域(计算配置)
	AxiGnrConvRegRgnGrpConvCfg* reg_region_grp_conv_cfg; // 寄存器域(组卷积模式配置)
	AxiGnrConvRegRgnFmapCfg* reg_region_fmap_cfg; // 寄存器域(特征图配置)
	AxiGnrConvRegRgnKrnCfg* reg_region_kernal_cfg; // 寄存器域(卷积核配置)
	AxiGnrConvRegRgnBufCfg* reg_region_buffer_cfg; // 寄存器域(缓存配置)
	AxiGnrConvRegRgnBNActCfg* reg_region_bn_act_cfg; // 寄存器域(批归一化与激活配置)

	BNParam* bn_params_mem; // BN参数存储器域

	AxiGnrConvProp property; // 加速器属性
}AxiGnrConvHandler;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int axi_generic_conv_init(AxiGnrConvHandler* handler, uint32_t baseaddr); // 初始化通用卷积处理单元

int axi_generic_conv_enable_cal_sub_sys(AxiGnrConvHandler* handler); // 使能计算子系统
void axi_generic_conv_disable_cal_sub_sys(AxiGnrConvHandler* handler); // 除能计算子系统
int axi_generic_conv_enable_pm_cnt(AxiGnrConvHandler* handler); // 使能性能监测计数器
void axi_generic_conv_disable_pm_cnt(AxiGnrConvHandler* handler); // 除能性能监测计数器
int axi_generic_conv_enable_bn_act_proc(AxiGnrConvHandler* handler); // 使能批归一化与激活处理单元
void axi_generic_conv_disable_bn_act_proc(AxiGnrConvHandler* handler); // 除能批归一化与激活处理单元
int axi_generic_conv_start(AxiGnrConvHandler* handler); // 启动通用卷积处理单元
uint8_t axi_generic_conv_is_busy(AxiGnrConvHandler* handler); // 判断通用卷积处理单元是否忙碌

int axi_generic_conv_cfg(AxiGnrConvHandler* handler, const AxiGnrConvCfg* cfg); // 配置通用卷积处理单元
void axi_generic_conv_wr_bn_param_mem(AxiGnrConvHandler* handler, BNParam* bn_param_buf, uint32_t num); // 写BN参数存储器

uint32_t axi_generic_conv_get_cmd_fns_n(AxiGnrConvHandler* handler, AxiGnrConvCmdFnsNQueryType query_type); // 查询DMA命令完成数
int axi_generic_conv_clr_cmd_fns_n(AxiGnrConvHandler* handler, AxiGnrConvCmdFnsNClrType clr_type); // 清除DMA命令完成数计数器
void axi_generic_conv_get_pm_cnt(AxiGnrConvHandler* handler, AxiGnrConvPerfMonsts* pm_sts); // 获取性能监测计数器的值
int axi_generic_conv_clr_pm_cnt(AxiGnrConvHandler* handler); // 清除性能监测计数器
