function [E,parts]=flight_energy_model(u,p,q,g)
assert(all(q>=0 & q<=u.payload+1e-9),'Payload outside defined range');
L=u.range0-(u.range0-u.rangeF).*(q/u.payload).^1.5;
horOut=u.energy*p.distance./L;horBack=u.energy*p.distance/u.range0;
upOut=(u.mass+q)*g*p.outUp/(u.eta*3.6e6);upBack=u.mass*g*p.backUp/(u.eta*3.6e6);
E=horOut+horBack+upOut+upBack;
parts=struct('horizontal_out',horOut,'horizontal_back',horBack,'climb_out',upOut,'climb_back',upBack);
end
