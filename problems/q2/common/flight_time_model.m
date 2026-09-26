function [operation,flight]=flight_time_model(u,p,n)
flight=(p.outUp+p.backUp)*(1/u.up+1/u.down)+2*p.distance/u.speed;
operation=flight+u.prep+n*u.load+u.handover+n*u.boxhandover;
end
