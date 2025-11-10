`ifndef __PANDA_ICB_MACROS_H
`define __PANDA_ICB_MACROS_H

`define panda_inside(VARIABLE, MIN, MAX) ((VARIABLE >= MIN) && (VARIABLE <= MAX))

`define panda_delay_constraint(DELAY, CONFIGURATION) \
if(CONFIGURATION.max_delay > CONFIGURATION.min_delay){ \
	`panda_inside(DELAY, CONFIGURATION.min_delay, CONFIGURATION.mid_delay[0]) || \
	`panda_inside(DELAY, CONFIGURATION.mid_delay[1], CONFIGURATION.max_delay); \
	if(CONFIGURATION.min_delay == 0){ \
		DELAY dist{ \
			0 := CONFIGURATION.weight_zero_delay, \
			[1:CONFIGURATION.mid_delay[0]] :/ CONFIGURATION.weight_short_delay, \
			[CONFIGURATION.mid_delay[1]:CONFIGURATION.max_delay] :/ CONFIGURATION.weight_long_delay \
		}; \
    }else{ \
		DELAY dist{ \
			[CONFIGURATION.min_delay:CONFIGURATION.mid_delay[0]] :/ CONFIGURATION.weight_short_delay, \
			[CONFIGURATION.mid_delay[1]:CONFIGURATION.max_delay] :/ CONFIGURATION.weight_long_delay \
		}; \
	} \
}else{ \
	DELAY == CONFIGURATION.min_delay; \
}

`define panda_array_delay_constraint(DELAY, CONFIGURATION) \
foreach(DELAY[__i]){ \
	`panda_delay_constraint(DELAY[__i], CONFIGURATION) \
}

`define panda_declare_begin_end_event_api(EVENT_TYPE) \
function void begin_``EVENT_TYPE``(time begin_time = 0); \
	if(``EVENT_TYPE``_begin_event.is_off()) \
	begin \
		this.``EVENT_TYPE``_begin_time = (begin_time <= 0) ? $time:begin_time; \
		this.``EVENT_TYPE``_begin_event.trigger(); \
	end \
endfunction \
function void end_``EVENT_TYPE``(time end_time = 0); \
	if(``EVENT_TYPE``_end_event.is_off()) \
	begin \
		this.``EVENT_TYPE``_end_time = (end_time <= 0) ? $time:end_time; \
		this.``EVENT_TYPE``_end_event.trigger(); \
	end \
endfunction \
function bit ``EVENT_TYPE``_began(); \
	return this.``EVENT_TYPE``_begin_event.is_on(); \
endfunction \
function bit ``EVENT_TYPE``_ended(); \
	return this.``EVENT_TYPE``_end_event.is_on(); \
endfunction

`define panda_put_fifo_to_dyn_arr(TYPE, FIELD_NAME) \
function void put_``FIELD_NAME``(const ref ``TYPE`` ``FIELD_NAME``[$]); \
	this.``FIELD_NAME`` = new[``FIELD_NAME``.size()]; \
	foreach(``FIELD_NAME``[i]) \
	begin \
		this.``FIELD_NAME``[i] = ``FIELD_NAME``[i]; \
	end \
endfunction

`define panda_get_element_from_dyn_arr(TYPE, FIELD_NAME) \
function ``TYPE`` get_``FIELD_NAME``(int index); \
	if(index < this.``FIELD_NAME``.size()) \
		return this.``FIELD_NAME``[index]; \
    else \
		return '0; \
endfunction

`define panda_print(VAR, FID) \
uvm_default_printer.knobs.mcd = FID; \
VAR.print(); \
uvm_default_printer.knobs.mcd = UVM_STDOUT;

`define panda_set_print_all_elements \
uvm_default_printer.knobs.begin_elements = -1;

`define panda_set_print_begin_elements_5 \
uvm_default_printer.knobs.begin_elements = 5;

`endif
