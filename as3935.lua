wifi.setmode(wifi.STATION)
wifi.sta.config("wlan","password")
timeout=30;
threshold_distance=10;
irq_event=0;
safe_to_power_on=0;
sensorgotdistance=20;
i2c.setup(0,3,4,i2c.SLOW);
gpio.mode(2, gpio.OUTPUT);
gpio.write(2, gpio.HIGH);
function rigisters_read( word_addr,size)
	i2c.start(0);
	i2c.address(0, 7 ,i2c.TRANSMITTER); --set for write
	i2c.write(0,word_addr); -- register address
	i2c.start(0);
	i2c.address(0, 1,i2c.RECEIVER); --setting for read
    local data=i2c.read(0,size); --read
    i2c.stop(0);
	return data
end
function byte_write(word_addr,mask,data)
	i2c.start(0);								--start i2c module 
	i2c.address(0, 6 ,i2c.TRANSMITTER); 		--set for writing to chip
	i2c.write(0,word_addr);						--write address
	i2c.write(0,data);						--write data
    i2c.stop(0);								--stop tranfer
end

function pin1cb( )
	local irq_source=rigister_read(0x03);
	if(bit.band(irq_source , 8)==8)then
		print("lightning");
		storm_at_distance=rigister_read(0x07);
		sensordistance=bit.band(storm_at_distance, 0x3F);
		print("Distance"..tostring(sensorgotdistance));
	end
	if(sensorgotdistance==1)then
		--lightning above you
		print("run");
		safe_to_power_on=0;	--0 means no
	end	
	if((sensorgotdistance>1)and(sensorgotdistance<63))then
		if(sensorgotdistance<=threshold_distance)then
			safe_to_power_on=0;
			waituntil=tmr.time()+timeout*60;
		else
			safe_to_power_on=1;
		end
	end
	if (safe_to_power_on==0 and waituntil<tmr.time()) then
		safe_to_power_on=1;
	end
	if(safe_to_power_on==1 and waituntil>tmr.time())then
		gpio.write(2, gpio.HIGH);
	else
	    gpio.write(2, gpio.LOW);
	end	
end

function set_device(t,d)
	timeout=t;
	distance=d;
	byte_write(0x3C,0xff,0x96);--reset
	byte_write(0x3D,0xff,0x96);--power up
	byte_write(0x8, 0xF, 3);--set calibration variable capacitor i think seller thold me that this one is 3
	byte_write(0x0, 0x1,0x0);--pwd
	byte_write(0x3D,0xff,0x96);--power up
	byte_write(0x3,0x20, 0x1);--disable disturbers (man made detections)
	byte_write(0x0,0x3E,0x12);

	gpio.mode(1,gpio.INT,gpio.PULLUP);
	gpio.trig(1, "up ",pin1cb);

end

srv=net.createServer(net.TCP)
srv:listen(80,function(conn)
    conn:on("receive", function(client,request)
        local buf = "";
        local _, _, method, path, vars = string.find(request, "([A-Z]+) (.+)?(.+) HTTP");
        if(method == nil)then
            _, _, method, path = string.find(request, "([A-Z]+) (.+) HTTP");
        end
        local _GET = {}
        if (vars ~= nil)then
            for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
                _GET[k] = v
            end
        end
        buf = buf.."<p>D:<a href=\"?pin=dm\"><button>-</button></a>&nbsp;<a href=\"?pin=dp\"><button>+</button></a></p>";
        buf = buf.."<p>T:<a href=\"?pin=tm\"><button>-</button></a>&nbsp;<a href=\"?pin=tp\"><button>+</button></a></p>";
        if(_GET.pin == "dm")then
			if(threshold_distance>0)then
				threshold_distance=threshold_distance-1
			end
        elseif(_GET.pin == "dp")then
            threshold_distance=threshold_distance+1
        elseif(_GET.pin == "tp")then
            timeout=timeout+15
        elseif(_GET.pin == "tp")then
			if(timeout>0)then
				timeout=timeout-15;
			end
        end
        buf = buf.."D:"..tostring(threshold_distance).."</p><p>T:"..tostring(timeout).."</p>";


        client:send(buf);
        client:close();
        collectgarbage();
        set_device(timeout,threshold_distance,cal_cap, in_out);
		collectgarbage();
		tmr.wdclr()
    end)
end)
