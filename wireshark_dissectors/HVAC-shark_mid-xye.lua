-- HVAC Shark Dissector
hvac_shark_proto = Proto("HVAC_Shark", "HVAC Shark Protocol")

-- Define the fields for the protocol
local f = hvac_shark_proto.fields
f.start_sequence = ProtoField.string("hvac_shark.start_sequence", "Start Sequence")
f.manufacturer = ProtoField.uint8("hvac_shark.manufacturer", "Manufacturer")
f.bus_type = ProtoField.uint8("hvac_shark.bus_type", "Bus Type")
f.reserved = ProtoField.uint8("hvac_shark.reserved", "Reserved")
f.data = ProtoField.bytes("hvac_shark.data", "Data")

-- Calculate and validate CRC
-- Data is summarized up to the last byte before the CRC-field, as well as the following byte after the crc-field
local function validate_crc(crc_input_data, length)
    local sum = 0
    for i = 0, length - 3 do
        sum = sum + crc_input_data(i, 1):uint()
    end
    sum = sum + crc_input_data( (length - 1), 1):uint()
    return 255 - (sum % 256)
end

-- Define the dissector function
function hvac_shark_proto.dissector(udp_payload_buffer, pinfo, tree)
    pinfo.cols.protocol = hvac_shark_proto.name

    local subtree = tree:add(hvac_shark_proto, udp_payload_buffer(), "HVAC Shark Protocol Data")

    -- Check for the start sequence "HVAC_shark"
    if udp_payload_buffer(0, 10):string() == "HVAC_shark" then
        subtree:add(f.start_sequence, udp_payload_buffer(0, 10))
        
        local manufacturer = udp_payload_buffer(10, 1):uint()
        local bus_type = udp_payload_buffer(11, 1):uint()
        
        if manufacturer == 1 then
            subtree:add(f.manufacturer, udp_payload_buffer(10, 1)):append_text(" (Midea)")
        else
            subtree:add(f.manufacturer, udp_payload_buffer(10, 1))
        end
        
        if bus_type == 0 then
            subtree:add(f.bus_type, udp_payload_buffer(11, 1)):append_text(" (Bus = XYE)")
        else
            subtree:add(f.bus_type, udp_payload_buffer(11, 1))
        end
        
        subtree:add(f.reserved, udp_payload_buffer(12, 1))

        -- Only further decode if manufacturer is Midea (1) and bus type is XYE (0)
        if manufacturer == 1 and bus_type == 0 then
            -- Decode the XYE protocol data
            local protocol_buffer = udp_payload_buffer(13, udp_payload_buffer:len() - 13)


            -- Add buffer length information
            local protocol_buffer_anotation_string = string.format("(Length: %d bytes - ", protocol_buffer:len())
            
            -- Early protocol validation
            if protocol_buffer:len() >= 3 then
                -- Extract and validate CRC
                local protocol_crc = protocol_buffer(protocol_buffer:len() - 2, 1):uint()
                local calculated_protocol_crc = validate_crc(protocol_buffer, protocol_buffer:len())
                
                protocol_buffer_anotation_string = protocol_buffer_anotation_string .. string.format("CRC: 0x%02X %s", 
                    protocol_crc,
                    calculated_protocol_crc == protocol_crc and " valid" or 
                    string.format(" invalid, calculated: 0x%02X", calculated_protocol_crc))
            end
            local data_subtree = subtree:add(f.data, udp_payload_buffer(13, udp_payload_buffer:len() - 13)):append_text(" " .. protocol_buffer_anotation_string .. ")")




            local protocol_length = protocol_buffer:len()
            if protocol_length == 16 then
                -- Decode frames with destination other than 0x80

                data_subtree:add(udp_payload_buffer(13, 1), "Preamble: " .. string.format("0x%02X", protocol_buffer(0, 1):uint()))
				
				local command_code = protocol_buffer(1, 1):uint()
				local command_name = "Unknown"
				
				if command_code == 0xc0 then
					command_name = "Query"
				elseif command_code == 0xc3 then
					command_name = "Set"
				elseif command_code == 0xcc then
					command_name = "Lock"
				elseif command_code == 0xcd then
					command_name = "Unlock"
				end
				
				data_subtree:add(udp_payload_buffer(14, 1), "Command: " .. string.format("0x%02X", command_code) .. " (" .. command_name .. ")")

                data_subtree:add(udp_payload_buffer(15, 1), "Destination: " .. string.format("0x%02X", protocol_buffer(2, 1):uint()))
                data_subtree:add(udp_payload_buffer(16, 1), "Source / Own ID: " .. string.format("0x%02X", protocol_buffer(3, 1):uint()))
                data_subtree:add(udp_payload_buffer(17, 1), "From Master: " .. string.format("0x%02X", protocol_buffer(4, 1):uint()))
                data_subtree:add(udp_payload_buffer(18, 1), "Source / Own ID: " .. string.format("0x%02X", protocol_buffer(5, 1):uint()))

                -- Decode payload if command is 0xc3 (set command)
                if protocol_buffer(1, 1):uint() == 0xc3 then
                    -- Decode byte 0x06
                    -- Decode the oper_mode field
                    local oper_mode = protocol_buffer(6, 1):uint()
                    local oper_mode_str = ""
                    if oper_mode == 0x00 then
                        oper_mode_str = "Off"
                    elseif oper_mode == 0x80 then
                        oper_mode_str = "Auto"
                    elseif oper_mode == 0x88 then
                        oper_mode_str = "Cool"
                    elseif oper_mode == 0x82 then
                        oper_mode_str = "Dry"
                    elseif oper_mode == 0x84 then
                        oper_mode_str = "Heat"
                    elseif oper_mode == 0x81 then
                        oper_mode_str = "Fan"
                    else
                        oper_mode_str = "Unknown"
                    end
                    data_subtree:add(udp_payload_buffer(19, 1), "Operating Mode: " .. string.format("0x%02X", oper_mode) .. " (" .. oper_mode_str .. ")")

                    -- Decode byte 0x07
                    -- Decode the fan field
                    local fan = protocol_buffer(7, 1):uint()
                    local fan_str = ""
                    if fan == 0x80 then
                        fan_str = "Auto"
                    elseif fan == 0x01 then
                        fan_str = "High"
                    elseif fan == 0x02 then
                        fan_str = "Medium"
                    elseif fan == 0x03 then
                        fan_str = "Low"
                    else
                        fan_str = "Unknown"
                    end
                    data_subtree:add(udp_payload_buffer(20, 1), "Fan: " .. string.format("0x%02X", fan) .. " (" .. fan_str .. ")")

                    data_subtree:add(udp_payload_buffer(21, 1), "Set Temp: " .. string.format("0x%02X", protocol_buffer(8, 1):uint()) .. " °C")

                    -- Decode byte 0x09
                    -- Decode the mode_flags field
                    local mode_flags = protocol_buffer(9, 1):uint()
                    local mode_flags_str = ""
                    if mode_flags == 0x02 then
                        mode_flags_str = "Aux Heat (Turbo)"
                    elseif mode_flags == 0x00 then
                        mode_flags_str = "Normal"
                    elseif mode_flags == 0x01 then
                        mode_flags_str = "ECO Mode (Sleep)"
                    elseif mode_flags == 0x04 then
                        mode_flags_str = "Swing"
                    elseif mode_flags == 0x88 then
                        mode_flags_str = "Ventilate"
                    else
                        mode_flags_str = "Unknown"
                    end
                    data_subtree:add(udp_payload_buffer(22, 1), "Mode Flags: " .. string.format("0x%02X", mode_flags) .. " (" .. mode_flags_str .. ")")

                    data_subtree:add(udp_payload_buffer(23, 1), "Timer Start: " .. string.format("0x%02X", protocol_buffer(10, 1):uint()))
                    data_subtree:add(udp_payload_buffer(24, 1), "Timer Stop: " .. string.format("0x%02X", protocol_buffer(11, 1):uint()))
                    data_subtree:add(udp_payload_buffer(25, 1), "Unknown: " .. string.format("0x%02X", protocol_buffer(12, 1):uint()))
                else
                    data_subtree:add(udp_payload_buffer(19, 7), "Payload: " .. tostring(protocol_buffer(6, 7):bytes()))
                end

                data_subtree:add(udp_payload_buffer(26, 1), "Command Check: " .. string.format("0x%02X", protocol_buffer(13, 1):uint()))
                data_subtree:add(udp_payload_buffer(27, 1), "CRC: " .. string.format("0x%02X", protocol_buffer(14, 1):uint()))
                data_subtree:add(udp_payload_buffer(28, 1), "Prologue: " .. string.format("0x%02X", protocol_buffer(15, 1):uint()))

                -- Validate CRC
                local calculated_crc = validate_crc(udp_payload_buffer(13, 16), 16)
                if calculated_crc == protocol_buffer(14, 1):uint() then
                    data_subtree:add(udp_payload_buffer(27, 1), "CRC: " .. string.format("0x%02X", protocol_buffer(14, 1):uint()) .. " (Valid)")
                else
                    data_subtree:add(udp_payload_buffer(27, 1), "CRC: " .. string.format("0x%02X", protocol_buffer(14, 1):uint()) .. " (Invalid, calculated: 0x%02X)", calculated_crc)
                end
            elseif protocol_length == 32 then
                -- Decode byte 0x00 (Preamble)
                data_subtree:add(udp_payload_buffer(13, 1), "Preamble: " .. string.format("0x%02X", protocol_buffer(0, 1):uint()))
                
                -- Decode byte 0x01
                -- Decode the response code field
                data_subtree:add(udp_payload_buffer(14, 1), "Response Code: " .. string.format("0x%02X", protocol_buffer(1, 1):uint()))

                -- Decode byte 0x02
                -- Decode the to_master field
                data_subtree:add(udp_payload_buffer(15, 1), "To Master: " .. string.format("0x%02X", protocol_buffer(2, 1):uint()))

                -- Decode byte 0x03
                -- Decode the destination field
                data_subtree:add(udp_payload_buffer(16, 1), "Destination: " .. string.format("0x%02X", protocol_buffer(3, 1):uint()))

                -- Decode byte 0x04
                -- Decode the source/own ID field
                data_subtree:add(udp_payload_buffer(17, 1), "Source/Own ID: " .. string.format("0x%02X", protocol_buffer(4, 1):uint()))

                -- Decode byte 0x05
                -- Decode the destination (masterID) field
                data_subtree:add(udp_payload_buffer(18, 1), "Destination (masterID): " .. string.format("0x%02X", protocol_buffer(5, 1):uint()))
                
                -- Decode byte 0x06
                -- Decode the unknown field as single bits
                local unknown_field = protocol_buffer(6, 1):uint()
                data_subtree:add(udp_payload_buffer(19, 1), "Unknown field: " .. string.format("0x%02X", unknown_field))
                for i = 0, 7 do
                    local bit_value = bit.band(bit.rshift(unknown_field, i), 0x01)
                    data_subtree:add(udp_payload_buffer(19, 1), string.format("Bit %d: %d", i, bit_value))
                end

                -- Decode byte 0x07
                -- Decode the capabilities field as single bits
                local capabilities = protocol_buffer(7, 1):uint()
                data_subtree:add(udp_payload_buffer(20, 1), "Capabilities: " .. string.format("0x%02X", capabilities))
                for i = 0, 7 do
                    local bit_value = bit.band(bit.rshift(capabilities, i), 0x01)
                    data_subtree:add(udp_payload_buffer(20, 1), string.format("Bit %d: %d", i, bit_value))
                end

                -- Decode byte 0x08
                -- Decode the oper_mode field
                local oper_mode = protocol_buffer(8, 1):uint()
                local oper_mode_str = ""
                if oper_mode == 0x00 then
                    oper_mode_str = "Off"
                elseif oper_mode == 0x80 then
                    oper_mode_str = "Auto"
                elseif oper_mode == 0x88 then
                    oper_mode_str = "Cool"
                elseif oper_mode == 0x82 then
                    oper_mode_str = "Dry"
                elseif oper_mode == 0x84 then
                    oper_mode_str = "Heat"
                elseif oper_mode == 0x81 then
                    oper_mode_str = "Fan"
                else
                    oper_mode_str = "Unknown"
                end
                data_subtree:add(udp_payload_buffer(21, 1), "Operating Mode: " .. string.format("0x%02X", oper_mode) .. " (" .. oper_mode_str .. ")")

                -- Decode byte 0x09
                -- Decode the fan field
                local fan = protocol_buffer(9, 1):uint()
                local fan_str = ""
                if fan == 0x80 then
                    fan_str = "Auto"
                elseif fan == 0x01 then
                    fan_str = "High"
                elseif fan == 0x02 then
                    fan_str = "Medium"
                elseif fan == 0x03 then
                    fan_str = "Low"
                else
                    fan_str = "Unknown"
                end
                data_subtree:add(udp_payload_buffer(22, 1), "Fan: " .. string.format("0x%02X", fan) .. " (" .. fan_str .. ")")
                
                -- Decode byte 0x0A (dec 10)
                -- Decode the set_temp field
                data_subtree:add(udp_payload_buffer(23, 1), "Set Temp: " .. string.format("0x%02X", protocol_buffer(10, 1):uint()))

                -- Decode byte 0x0B (dec 11)
                -- Decode the T1_temp field
                data_subtree:add(udp_payload_buffer(24, 1), "T1 Temp: " .. string.format("0x%02X", protocol_buffer(11, 1):uint()))

                -- Decode byte 0x0C (dec 12)
                -- Decode the T2A_temp field
                data_subtree:add(udp_payload_buffer(25, 1), "T2A Temp: " .. string.format("0x%02X", protocol_buffer(12, 1):uint()))

                -- Decode byte 0x0D (dec 13)
                -- Decode the T2B_temp field
                data_subtree:add(udp_payload_buffer(26, 1), "T2B Temp: " .. string.format("0x%02X", protocol_buffer(13, 1):uint()))

                -- Decode byte 0x0E (dec 14)
                -- Decode the T3_temp field
                data_subtree:add(udp_payload_buffer(27, 1), "T3 Temp: " .. string.format("0x%02X", protocol_buffer(14, 1):uint()))

                -- Decode byte 0x0F (dec 15)
                -- Decode the current field
                data_subtree:add(udp_payload_buffer(28, 1), "Current: " .. string.format("0x%02X", protocol_buffer(15, 1):uint()))

                -- Decode byte 0x10 (dec 16)
                -- Decode the unknown field
                data_subtree:add(udp_payload_buffer(29, 1), "Unknown: " .. string.format("0x%02X", protocol_buffer(16, 1):uint()))
 
                -- Decode byte 0x11 (dec 17)
                -- Decode the timer_start field
                local timer_start = protocol_buffer(17, 1):uint()
                local hours_start = math.floor((timer_start % 128) * 15 / 60)
                local minutes_start = (timer_start % 128) * 15 % 60
                data_subtree:add(udp_payload_buffer(30, 1), "Timer Start: " .. string.format("0x%02X", timer_start) .. 
                    string.format(" (Hours: %d, Minutes: %d)", hours_start, minutes_start))
                
                -- Decode byte 0x12 (dec 18)
                -- Decode the timer_stop field
                local timer_stop = protocol_buffer(18, 1):uint()
                local hours_stop = math.floor((timer_stop % 128) * 15 / 60)
                local minutes_stop = (timer_stop % 128) * 15 % 60
                data_subtree:add(udp_payload_buffer(31, 1), "Timer Stop: " .. string.format("0x%02X", timer_stop) .. 
                    string.format(" (Hours: %d, Minutes: %d)", hours_stop, minutes_stop))
                
                data_subtree:add(udp_payload_buffer(32, 1), "Run: " .. string.format("0x%02X", protocol_buffer(19, 1):uint()))
                data_subtree:add(udp_payload_buffer(33, 1), "Mode Flags: " .. string.format("0x%02X", protocol_buffer(20, 1):uint()))
                data_subtree:add(udp_payload_buffer(34, 1), "Operating Flags: " .. string.format("0x%02X", protocol_buffer(21, 1):uint()))
                data_subtree:add(udp_payload_buffer(35, 1), "Error E (0..7): " .. string.format("0x%02X", protocol_buffer(22, 1):uint()))
                data_subtree:add(udp_payload_buffer(36, 1), "Error E (7..f): " .. string.format("0x%02X", protocol_buffer(23, 1):uint()))
                data_subtree:add(udp_payload_buffer(37, 1), "Protect P (0..7): " .. string.format("0x%02X", protocol_buffer(24, 1):uint()))
                data_subtree:add(udp_payload_buffer(38, 1), "Protect P (7..f): " .. string.format("0x%02X", protocol_buffer(25, 1):uint()))
                data_subtree:add(udp_payload_buffer(39, 1), "CCM Comm Error: " .. string.format("0x%02X", protocol_buffer(26, 1):uint()))
                data_subtree:add(udp_payload_buffer(40, 1), "Unknown 1: " .. string.format("0x%02X", protocol_buffer(27, 1):uint()))
                data_subtree:add(udp_payload_buffer(41, 1), "Unknown 2: " .. string.format("0x%02X", protocol_buffer(28, 1):uint()))
              
                -- Validate CRC for 32-byte protocol length
                local crc_80 = protocol_buffer(30, 1):uint()
                local calculated_crc_80 = validate_crc(udp_payload_buffer(13, 32), 32)

                if calculated_crc_80 == crc_80 then
                    data_subtree:add(udp_payload_buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Valid)")
                else
                    data_subtree:add(udp_payload_buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Invalid, calculated: 0x%02X)", calculated_crc_80)
                end

                -- Add Prologue field
                data_subtree:add(udp_payload_buffer(43, 1), "Prologue: " .. string.format("0x%02X", protocol_buffer(31, 1):uint()))



            else
                 -- Print the data for longer buffers
                data_subtree:add(udp_payload_buffer(13, protocol_buffer:len()), "Data: " .. tostring(protocol_buffer:bytes()))
            end
        end
    end
end

-- Register the dissector
local udp_port = DissectorTable.get("udp.port")
udp_port:add(22222, hvac_shark_proto)