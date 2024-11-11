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
            local data_subtree = subtree:add(f.data, udp_payload_buffer(13, udp_payload_buffer:len() - 13))
            local protocol_buffer = udp_payload_buffer(13, udp_payload_buffer:len() - 13)

            -- Early protocol validation
            if protocol_buffer:len() >= 3 then
                -- Add buffer length information
                data_subtree:add(udp_payload_buffer(13, 1), string.format("Protocol Buffer Length: %d bytes", protocol_buffer:len()))
                
                -- Extract and validate CRC
                local protocol_crc = protocol_buffer(protocol_buffer:len() - 2, 1):uint()
                local calculated_protocol_crc = validate_crc(protocol_buffer, protocol_buffer:len())
                
                data_subtree:add(udp_payload_buffer(13 + protocol_buffer:len() - 2, 1), 
                    string.format("Protocol CRC: 0x%02X %s", 
                        protocol_crc,
                        calculated_protocol_crc == protocol_crc and "(Valid)" or 
                        string.format("(Invalid, calculated: 0x%02X)", calculated_protocol_crc)))
            end



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
                data_subtree:add(udp_payload_buffer(13, 1), "Preamble: " .. string.format("0x%02X", protocol_buffer(0, 1):uint()))
                data_subtree:add(udp_payload_buffer(14, 1), "Response Code: " .. string.format("0x%02X", protocol_buffer(1, 1):uint()))
                data_subtree:add(udp_payload_buffer(15, 1), "To Master: " .. string.format("0x%02X", protocol_buffer(2, 1):uint()))
                data_subtree:add(udp_payload_buffer(16, 1), "Destination: " .. string.format("0x%02X", protocol_buffer(3, 1):uint()))
                data_subtree:add(udp_payload_buffer(17, 1), "Source/Own ID: " .. string.format("0x%02X", protocol_buffer(4, 1):uint()))
                data_subtree:add(udp_payload_buffer(18, 1), "Destination (masterID): " .. string.format("0x%02X", protocol_buffer(5, 1):uint()))
                data_subtree:add(udp_payload_buffer(19, 1), "Unclear: " .. string.format("0x%02X", protocol_buffer(6, 1):uint()))
                data_subtree:add(udp_payload_buffer(20, 1), "Capabilities: " .. string.format("0x%02X", protocol_buffer(7, 1):uint()))

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

                data_subtree:add(udp_payload_buffer(22, 1), "Fan: " .. string.format("0x%02X", protocol_buffer(9, 1):uint()))
                data_subtree:add(udp_payload_buffer(23, 1), "Set Temp: " .. string.format("0x%02X", protocol_buffer(10, 1):uint()))
                data_subtree:add(udp_payload_buffer(24, 1), "T1 Temp: " .. string.format("0x%02X", protocol_buffer(11, 1):uint()))
                data_subtree:add(udp_payload_buffer(25, 1), "T2A Temp: " .. string.format("0x%02X", protocol_buffer(12, 1):uint()))
                data_subtree:add(udp_payload_buffer(26, 1), "T2B Temp: " .. string.format("0x%02X", protocol_buffer(13, 1):uint()))
                data_subtree:add(udp_payload_buffer(27, 1), "T3 Temp: " .. string.format("0x%02X", protocol_buffer(14, 1):uint()))
                data_subtree:add(udp_payload_buffer(28, 1), "Current: " .. string.format("0x%02X", protocol_buffer(15, 1):uint()))
                data_subtree:add(udp_payload_buffer(29, 1), "Frequency: " .. string.format("0x%02X", protocol_buffer(16, 1):uint()))
                data_subtree:add(udp_payload_buffer(30, 1), "Timer Start: " .. string.format("0x%02X", protocol_buffer(17, 1):uint()))
                data_subtree:add(udp_payload_buffer(31, 1), "Timer Stop: " .. string.format("0x%02X", protocol_buffer(18, 1):uint()))
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
                data_subtree:add(udp_payload_buffer(42, 1), "CRC: " .. string.format("0x%02X", protocol_buffer(30, 1):uint()))
                data_subtree:add(udp_payload_buffer(43, 1), "Prologue: " .. string.format("0x%02X", protocol_buffer(31, 1):uint()))

                -- Validate CRC
                local crc_80 = protocol_buffer(30, 1):uint()
                local calculated_crc_80 = validate_crc(udp_payload_buffer(13, 32), 32)
                if calculated_crc_80 == crc_80 then
                    data_subtree:add(udp_payload_buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Valid)")
                else
                    data_subtree:add(udp_payload_buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Invalid, calculated: 0x%02X)", calculated_crc_80)
                end

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