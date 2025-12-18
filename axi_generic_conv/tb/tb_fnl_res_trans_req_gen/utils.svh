`ifndef __UTILS_H

`define __UTILS_H

class Util;
	
	local static uvm_tree_printer object_printer = null;
	
	static function int unsigned ofmap_data_type_to_int(ofmap_data_type_t d);
		case(d)
			DATA_1_BYTE: return 1;
			DATA_2_BYTE: return 2;
			DATA_4_BYTE: return 4;
			default: return 1;
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
