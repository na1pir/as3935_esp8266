wifi.setmode(wifi.STATION)
wifi.sta.config("wlan","password")
--tmr.delay(1000)--just a bit of delay so everithing comes to equilibrium 

timeout=30;
threshold_distance=10;
irq_event=0;
safe_to_power_on=0; --power should be off before inicialization 
waituntil=0;
sensorgotdistance=20;
in_out=1;
cal_cap=3;
calib=0;

i2c.setup(0,3,4,i2c.SLOW);
gpio.mode(2, gpio.OUTPUT);
gpio.write(2, gpio.HIGH);
    
function rigisters_read( word_addr,size)
	i2c.start(0);
	i2c.address(0, 0 ,i2c.TRANSMITTER); --set for write
	i2c.write(0,word_addr); -- register address
	i2c.start(0);
	i2c.address(0, 1,i2c.RECEIVER); --setting for read
    local data=i2c.read(0,size); --read
    i2c.stop(0);
    --print("ra:"..tostring(word_addr).."d:"..tostring(data));
	return data
end
function byte_write(word_addr,mask,data)
	local old_reg=rigisters_read(word_addr,1);  			--read register
	old_reg=bit.band(0xff,bit.bnot(mask));  	--save data outside mask
	ored_data=bit.bor(old_reg,data);				--take data outside maske and add new data
	i2c.start(0);								--start i2c module 
	i2c.address(0, 0 ,i2c.TRANSMITTER); 		--set for writing to chip
	i2c.write(0,word_addr);						--write address
	i2c.write(0,ored_data);						--write data
    i2c.stop(0);								--stop tranfer
    --print("wa:"..tostring(word_addr).."od:"..tostring(old_reg).."nd:"..tostring(ored_data));
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

function set_device(t,d,c,cb,in_out)
	timeout=t;
	distance=d;
	cal_cap=c;
	calib=cb;
	byte_write(0x3C,0xff,0x96);--reset
	byte_write(0x3D,0xff,0x96);--power up
	byte_write(0x8, 0xF, cal_cap);--set calibration variable capacitor
	byte_write(0x0, 0x1,0x0);--pwd
	byte_write(0x3D,0xff,0x96);--power up
	byte_write(0x3,0x20, 0x1);--disable disturbers (man made detections)
	if(in_out==1)then
		byte_write(0x0,0x3E,0x12);
	else
		byte_write(0x0,0x3E,0xE);
	end
	if(calib==1)then
		byte_write(0x3, 0xC0,0x0);--divider to 16
		byte_write(0x8, 0x80,0x1);--link LC-Oscilator on irq pin for tuning
	else
		gpio.mode(1,gpio.INT,gpio.PULLUP);
		gpio.trig(1, "up ",pin1cb);
	end
	print("setup"..tostring(t).."."..tostring(d).."."..tostring(c).."."..tostring(cb).."."..tostring(in_out))
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
        buf = buf.."<p>Distance:<a href=\"?pin=dm\"><button>-</button></a>&nbsp;<a href=\"?pin=dp\"><button>+</button></a></p>";
        buf = buf.."<p>Timeout:<a href=\"?pin=tm\"><button>-</button></a>&nbsp;<a href=\"?pin=tp\"><button>+</button></a></p>";
        buf = buf.."<p>Calibration cap:<a href=\"?pin=inc\"><button>+</button></a>&nbsp;<a href=\"?pin=dec\"><button>-</button></a></p>";
        buf = buf.."<p>in/out door:<a href=\"?pin=in\"><button>in</button></a>&nbsp;<a href=\"?pin=out\"><button>out</button></a></p>";
        buf = buf.."<p>lco calibration / lightning detection:<a href=\"?pin=cal\"><button>calibration</button></a>&nbsp;<a href=\"?pin=det\"><button>detection</button></a></p>";
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
        elseif(_GET.pin == "inc")then
            if(cal_cap<15)then
				cal_cap=cal_cap+1
			end
        elseif(_GET.pin == "dec")then
            if(timeout>0)then
				cal_cap=cal_cap-1
			end
		elseif(_GET.pin == "in")then
            in_out=1
        elseif(_GET.pin == "out")then
			in_out=0
		elseif(_GET.pin == "cal")then
            calib=1
        elseif(_GET.pin == "det")then
			calib=0
        end
        buf = buf.."Distance:"..tostring(threshold_distance).."</p><p>Timeout:"..tostring(timeout).."<p>Calibration capacitor:"..tostring(cal_cap).."</p><p>Location:";
        
        if(in_out==1)then
			buf = buf.."in</p>";
        else
			buf = buf.."out</p>";
        end
        buf = buf.."</p>mode: "
        
        if(calib==1)then
			buf = buf.."calibration mode</p>";
        else
			buf = buf.."Lightning detection</p>";
        end
        client:send(buf);
        client:close();
        set_device(timeout,threshold_distance,cal_cap,calib, in_out);
		--collectgarbage();
		--tmr.wdclr()
    end)
end)
