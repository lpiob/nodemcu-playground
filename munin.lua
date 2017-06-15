-- simple lua munin-node implementation

-- 
BMP_OSS = 3 -- oversampling setting (0-3)
BMP_SDA_PIN = 4 -- sda pin, GPIO2
BMP_SCL_PIN = 5 -- scl pin, GPIO0

DHT_PIN=8

local humidity=0
tmr.alarm(2, 10000, tmr.ALARM_AUTO, function()
    local status, temp, humi = dht.read11(DHT_PIN)
    if status == dht.OK then
        humidity=humi
    end
end)

bmp180 = require("bmp180")
bmp180.init(BMP_SDA_PIN, BMP_SCL_PIN)

-- munin


local munin={
 ["hostname"]="esp8266",
 ["allowed_ips"]={
    ["192.168.0.56"]=true, -- lbiegaj
    ["192.168.1.91"]=true, -- munin biuro
 },
 ["plugins"]={
     ["pressure"]=function(arg)
       if arg=="config" then
        return [[graph_title Air pressure
graph_category Weather
graph_scale no
graph_args --units-exponent 0 --lower-limit 930 --upper-limit 1070 --rigid
pressure.label hPa
pressure.draw AREA
pressure.type GAUGE
pressure.max 1100
pressure.min 900
.
]]
       else
        bmp180.read(BMP_OSS)
        local p = bmp180.getPressure()
        return "pressure.value "..(p/100).."\n.\n"
       end
    end,
    ["temperature"]=function(arg)
       if arg=="config" then
        return [[graph_title Temperature
graph_category Weather
graph_period Celsius
temperature.label Temperature
temperature.draw AREA
temperature.min -10
temperature.max 100
.
]]
       else
        bmp180.read(BMP_OSS)
        local t = bmp180.getTemperature()
        return "temperature.value "..(t/10).."\n.\n"
       end
    end,
    ["humidity"]=function(arg)
       if arg=="config" then
        return [[graph_title Humidity
graph_category Weather
graph_period %hum
humidity.label Humidity
humidity.draw AREA
humidity.min 0
humidity.max 100
.
]]
       else
        return "humidity.value "..(humidity).."\n.\n"
       end
    end
 }
}

munin.process_command=function(conn, command)
    words = {}
    for word in command:gmatch("%w+") do table.insert(words, word) end
    if #words<1 then
        return conn:close()
    end
    
    if words[1]=="quit" then
        return conn:close()
    elseif words[1]=="list" then
        for i,_ in pairs(munin.plugins) do
            conn:send(i.." ")
        end
        return conn:send("\n")
    elseif words[1]=="config" and munin.plugins[words[2]] then
        return conn:send( munin.plugins[words[2]]("config") )
    elseif words[1]=="fetch" and munin.plugins[words[2]] then
        return conn:send( munin.plugins[words[2]]("fetch") )
    elseif words[1]=="cap" then
        return conn:send("cap multigraph dirtyconfig\n")
    else
        return conn:send("# unknown command: "..command.."\n")
    end
end

munin.start_server=function()
    munin.srv = net.createServer(net.TCP, 180)

    local cnt=0
    for i,v in pairs(munin.plugins) do
        cnt=cnt+1
    end
    -- nie startujemy, jesli nie mamy pluginow!
    if cnt<=0 then
        return false
    end
    
    munin.srv:listen(4949, function(socket)
        local str=""
    
        socket:on("connection", function(s, up)
            local _,remote_ip=s:getpeer()
            
            -- sprawdzamy czy zdalny host moze sie z nami polaczyc
            if not munin.allowed_ips[remote_ip] then
             return s:close()
            else
             -- wysylamy banner
             s:send("# munin node at "..munin.hostname.."\n")
            end
        end)
        
        socket:on("receive", function(s, l)
            str=str..l
            str=str:gsub("\r", "") -- munin wysyla tylko \n, ale telnet juz uzywa \r
            local m
            
            repeat
                m=string.find(str, "\n")
            
                if m then
                    local command=string.sub(str, 1, m-1)
                    str=string.sub(str, m+1)
                    munin.process_command(s, command)
                end
            until not m
        end)
    
    end)
end

munin.start_server()

-- http server
srv = net.createServer(net.TCP) 
srv:listen(80,function(conn)  

conn:on("connection", function(s, up)
    local _,remote_ip=s:getpeer()
    
    -- sprawdzamy czy zdalny host moze sie z nami polaczyc
    if not munin.allowed_ips[remote_ip] then
     return s:close()
    end
end)
  
conn:on("receive",function(conn,payload) 
    bmp180.read(BMP_OSS)
    local p = bmp180.getPressure()/100
    local t = bmp180.getTemperature()/10
    local str=string.format('{"temperature":%.4f,"pressure":%.4f,"humidity":%d}', t, p, humidity)
    conn:send(str)
        

    conn:on("sent", function(conn) conn:close() end)
end)
end)
