`ifndef __UTILS_H

`define __UTILS_H

import "DPI-C" function int unsigned encode_fp16(input real d);
import "DPI-C" function real decode_fp16(input int unsigned fp16);

class Util;
	
	local static uvm_tree_printer object_printer = null;
	
	static function int unsigned kernal_sz_t_to_int(kernal_sz_t sz);
		case(sz)
			KBUFGRPSZ_1x1: return 1 * 1;
			KBUFGRPSZ_3x3: return 3 * 3;
			KBUFGRPSZ_5x5: return 5 * 5;
			KBUFGRPSZ_7x7: return 7 * 7;
			KBUFGRPSZ_9x9: return 9 * 9;
			KBUFGRPSZ_11x11: return 11 * 11;
		endcase
	endfunction
	
	static function int unsigned kernal_sz_t_to_w_h(kernal_sz_t sz);
		case(sz)
			KBUFGRPSZ_1x1: return 1;
			KBUFGRPSZ_3x3: return 3;
			KBUFGRPSZ_5x5: return 5;
			KBUFGRPSZ_7x7: return 7;
			KBUFGRPSZ_9x9: return 9;
			KBUFGRPSZ_11x11: return 11;
		endcase
	endfunction
	
	static function int unsigned kernal_wgtblk_sfc_n_t_to_int(wgtblk_sfc_n_t sfc_n);
		case(sfc_n)
			WGTBLK_SFC_N_1: return 1;
			WGTBLK_SFC_N_2: return 2;
			WGTBLK_SFC_N_4: return 4;
			WGTBLK_SFC_N_8: return 8;
			WGTBLK_SFC_N_16: return 16;
			WGTBLK_SFC_N_32: return 32;
			WGTBLK_SFC_N_64: return 64;
			WGTBLK_SFC_N_128: return 128;
		endcase
	endfunction
	
	static function uvm_tree_printer get_object_printer();
		if(object_printer == null)
		begin
			object_printer = new();
			
			`panda_set_print_all_elements(object_printer)
		end
		
		return object_printer;
	endfunction
	
endclass
	
`endif
