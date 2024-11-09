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
local function validate_crc(buffer, length)
    local sum = 0
    for i = 0, length - 1 do
        sum = sum + buffer(i, 1):uint()
    end
    return 255 - (sum % 256) + 1
end

-- Define the dissector function
function hvac_shark_proto.dissector(buffer, pinfo, tree)
    pinfo.cols.protocol = hvac_shark_proto.name

    local subtree = tree:add(hvac_shark_proto, buffer(), "HVAC Shark Protocol Data")

    -- Check for the start sequence "HVAC_shark"
    if buffer(0, 10):string() == "HVAC_shark" then
        subtree:add(f.start_sequence, buffer(0, 10))
        
        local manufacturer = buffer(10, 1):uint()
        local bus_type = buffer(11, 1):uint()
        
        if manufacturer == 1 then
            subtree:add(f.manufacturer, buffer(10, 1)):append_text(" (Midea)")
        else
            subtree:add(f.manufacturer, buffer(10, 1))
        end
        
        if bus_type == 0 then
            subtree:add(f.bus_type, buffer(11, 1)):append_text(" (Bus = XYE)")
        else
            subtree:add(f.bus_type, buffer(11, 1))
        end
        
        subtree:add(f.reserved, buffer(12, 1))

        -- Only further decode if manufacturer is Midea (1) and bus type is XYE (0)
        if manufacturer == 1 and bus_type == 0 then
            -- Decode the XYE protocol data
            local data_subtree = subtree:add(f.data, buffer(13, buffer:len() - 13))
            local data_buffer = buffer(13, buffer:len() - 13)

            -- Check if the destination is 0x80
            if data_buffer(2, 1):uint() == 0x80 then
                -- Decode frames with destination 0x80

                data_subtree:add(buffer(13, 1), "Preamble: " .. string.format("0x%02X", data_buffer(0, 1):uint()))
                data_subtree:add(buffer(14, 1), "Response Code: " .. string.format("0x%02X", data_buffer(1, 1):uint()))
                data_subtree:add(buffer(15, 1), "To Master: " .. string.format("0x%02X", data_buffer(2, 1):uint()))
                data_subtree:add(buffer(16, 1), "Destination: " .. string.format("0x%02X", data_buffer(3, 1):uint()))
                data_subtree:add(buffer(17, 1), "Source/Own ID: " .. string.format("0x%02X", data_buffer(4, 1):uint()))
                data_subtree:add(buffer(18, 1), "Destination (masterID): " .. string.format("0x%02X", data_buffer(5, 1):uint()))
                data_subtree:add(buffer(19, 1), "Unclear: " .. string.format("0x%02X", data_buffer(6, 1):uint()))
                data_subtree:add(buffer(20, 1), "Capabilities: " .. string.format("0x%02X", data_buffer(7, 1):uint()))

                -- Decode byte 0x08
                -- Decode the oper_mode field
                local oper_mode = data_buffer(8, 1):uint()
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
                data_subtree:add(buffer(21, 1), "Operating Mode: " .. string.format("0x%02X", oper_mode) .. " (" .. oper_mode_str .. ")")

                data_subtree:add(buffer(22, 1), "Fan: " .. string.format("0x%02X", data_buffer(9, 1):uint()))
                data_subtree:add(buffer(23, 1), "Set Temp: " .. string.format("0x%02X", data_buffer(10, 1):uint()))
                data_subtree:add(buffer(24, 1), "T1 Temp: " .. string.format("0x%02X", data_buffer(11, 1):uint()))
                data_subtree:add(buffer(25, 1), "T2A Temp: " .. string.format("0x%02X", data_buffer(12, 1):uint()))
                data_subtree:add(buffer(26, 1), "T2B Temp: " .. string.format("0x%02X", data_buffer(13, 1):uint()))
                data_subtree:add(buffer(27, 1), "T3 Temp: " .. string.format("0x%02X", data_buffer(14, 1):uint()))
                data_subtree:add(buffer(28, 1), "Current: " .. string.format("0x%02X", data_buffer(15, 1):uint()))
                data_subtree:add(buffer(29, 1), "Frequency: " .. string.format("0x%02X", data_buffer(16, 1):uint()))
                data_subtree:add(buffer(30, 1), "Timer Start: " .. string.format("0x%02X", data_buffer(17, 1):uint()))
                data_subtree:add(buffer(31, 1), "Timer Stop: " .. string.format("0x%02X", data_buffer(18, 1):uint()))
                data_subtree:add(buffer(32, 1), "Run: " .. string.format("0x%02X", data_buffer(19, 1):uint()))
                data_subtree:add(buffer(33, 1), "Mode Flags: " .. string.format("0x%02X", data_buffer(20, 1):uint()))
                data_subtree:add(buffer(34, 1), "Operating Flags: " .. string.format("0x%02X", data_buffer(21, 1):uint()))
                data_subtree:add(buffer(35, 1), "Error E (0..7): " .. string.format("0x%02X", data_buffer(22, 1):uint()))
                data_subtree:add(buffer(36, 1), "Error E (7..f): " .. string.format("0x%02X", data_buffer(23, 1):uint()))
                data_subtree:add(buffer(37, 1), "Protect P (0..7): " .. string.format("0x%02X", data_buffer(24, 1):uint()))
                data_subtree:add(buffer(38, 1), "Protect P (7..f): " .. string.format("0x%02X", data_buffer(25, 1):uint()))
                data_subtree:add(buffer(39, 1), "CCM Comm Error: " .. string.format("0x%02X", data_buffer(26, 1):uint()))
                data_subtree:add(buffer(40, 1), "Unknown 1: " .. string.format("0x%02X", data_buffer(27, 1):uint()))
                data_subtree:add(buffer(41, 1), "Unknown 2: " .. string.format("0x%02X", data_buffer(28, 1):uint()))
                data_subtree:add(buffer(42, 1), "CRC: " .. string.format("0x%02X", data_buffer(29, 1):uint()))
                data_subtree:add(buffer(43, 1), "Prologue: " .. string.format("0x%02X", data_buffer(30, 1):uint()))

                -- Validate CRC
                local crc_80 = data_buffer(29, 1):uint()
                local calculated_crc_80 = validate_crc(buffer(13, 29), 29)
                if calculated_crc_80 == crc_80 then
                    data_subtree:add(buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Valid)")
                else
                    data_subtree:add(buffer(42, 1), "CRC: " .. string.format("0x%02X", crc_80) .. " (Invalid, calculated: 0x%02X)", calculated_crc_80)
                end

            else
                -- Decode frames with destination other than 0x80

                data_subtree:add(buffer(13, 1), "Preamble: " .. string.format("0x%02X", data_buffer(0, 1):uint()))
				
				local command_code = data_buffer(1, 1):uint()
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
				
				data_subtree:add(buffer(14, 1), "Command: " .. string.format("0x%02X", command_code) .. " (" .. command_name .. ")")

                data_subtree:add(buffer(15, 1), "Destination: " .. string.format("0x%02X", data_buffer(2, 1):uint()))
                data_subtree:add(buffer(16, 1), "Source / Own ID: " .. string.format("0x%02X", data_buffer(3, 1):uint()))
                data_subtree:add(buffer(17, 1), "From Master: " .. string.format("0x%02X", data_buffer(4, 1):uint()))
                data_subtree:add(buffer(18, 1), "Source / Own ID: " .. string.format("0x%02X", data_buffer(5, 1):uint()))

                -- Decode payload if command is 0xc3 (set command)
                if data_buffer(1, 1):uint() == 0xc3 then
                    -- Decode byte 0x06
                    -- Decode the oper_mode field
                    local oper_mode = data_buffer(6, 1):uint()
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
                    data_subtree:add(buffer(19, 1), "Operating Mode: " .. string.format("0x%02X", oper_mode) .. " (" .. oper_mode_str .. ")")

                    -- Decode byte 0x07
                    -- Decode the fan field
                    local fan = data_buffer(7, 1):uint()
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
                    data_subtree:add(buffer(20, 1), "Fan: " .. string.format("0x%02X", fan) .. " (" .. fan_str .. ")")

                    data_subtree:add(buffer(21, 1), "Set Temp: " .. string.format("0x%02X", data_buffer(8, 1):uint()) .. " °C")

                    -- Decode byte 0x09
                    -- Decode the mode_flags field
                    local mode_flags = data_buffer(9, 1):uint()
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
                    data_subtree:add(buffer(22, 1), "Mode Flags: " .. string.format("0x%02X", mode_flags) .. " (" .. mode_flags_str .. ")")

                    data_subtree:add(buffer(23, 1), "Timer Start: " .. string.format("0x%02X", data_buffer(10, 1):uint()))
                    data_subtree:add(buffer(24, 1), "Timer Stop: " .. string.format("0x%02X", data_buffer(11, 1):uint()))
                    data_subtree:add(buffer(25, 1), "Unknown: " .. string.format("0x%02X", data_buffer(12, 1):uint()))
                else
                    data_subtree:add(buffer(19, 7), "Payload: " .. tostring(data_buffer(6, 7):bytes()))
                end

                data_subtree:add(buffer(26, 1), "Command Check: " .. string.format("0x%02X", data_buffer(13, 1):uint()))
                data_subtree:add(buffer(27, 1), "CRC: " .. string.format("0x%02X", data_buffer(14, 1):uint()))
                data_subtree:add(buffer(28, 1), "Prologue: " .. string.format("0x%02X", data_buffer(15, 1):uint()))

                -- Validate CRC
                local calculated_crc = validate_crc(buffer(13, 16), 16)
                if calculated_crc == data_buffer(14, 1):uint() then
                    data_subtree:add(buffer(27, 1), "CRC: " .. string.format("0x%02X", data_buffer(14, 1):uint()) .. " (Valid)")
                else
                    data_subtree:add(buffer(27, 1), "CRC: " .. string.format("0x%02X", data_buffer(14, 1):uint()) .. " (Invalid, calculated: 0x%02X)", calculated_crc)
                end
            end
        end
    end
end

-- Register the dissector
local udp_port = DissectorTable.get("udp.port")
udp_port:add(22222, hvac_shark_proto)