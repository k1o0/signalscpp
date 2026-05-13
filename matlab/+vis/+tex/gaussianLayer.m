function [layer, img] = gaussianLayer(pos, sigma)
% VIS.GAUSSIANLAYER Return a texture layer and image for a 2D Gaussian
%  Inputs:
%    pos - array of the form [azimuth altitude] defining the position of
%      the Gaussian (position of the centre pixel in visual degrees)
%    sigma - the size of the window in visual degrees.  Must be an array of
%      the form [width height].  
%
%  Outputs:
%    layer - the texture layer containing information about the texture,
%      e.g. size, position, orientation
%    img - the texture image as a 2D array of pixel intensity values
%      between 0 and 1
%
%  See also VIS.SINUSOIDLAYER, VIS.EMPTYLAYER, VIS.GRATING

%%% Gaussian of unit sigma: exp( -0.5*x^2 )
% If a Gaussian of unit sigma is sampled at 61 equally spaced points
% between x = +/-3.6, the values at the edges will be < 0.5/256, and linear
% interpolation between adjacent samples will have a max error < 0.5/256.
% An odd number means we hit the peak of the Gaussian == 1 at the centre
% pixel.
%
% Thus there is no point in sampling a Gaussian at a higher resolution or
% at more extreme points:
extend = 1;% increase this from one to avoid needing to repeat edges
xlimit = extend*18/5;% A gaussian is ~0.4/256 at this point
np = extend*61; % dx = ~0.12, max linear interp error = ~0.46/256

p = single(linspace(-xlimit, xlimit, np));
img = bsxfun(@times, exp( -0.5*p.^2 ), exp( -0.5*p.^2 )');

layer = vis.tex.emptyLayer();
layer.texOffset = pos;
layer.size = [(2*xlimit)*sigma(1); (2*xlimit)*sigma(2)];
layer.isPeriodic = false;

end

