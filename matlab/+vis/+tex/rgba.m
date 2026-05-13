function [img, sz] = rgba(colour, alpha)
% VIS.RGBA Return the input image as a column vector in the form required by
% glTexImage2D along with its original size
%  Takes matrix representing an image and converts it to uint8 RGBA colour
%  space.
%
%  Inputs:
%    colour - the image as either a 2D matrix of luminance values or a 3D
%      RGB matrix
%    alpha - the alpha values for the image.  May be either a scalar
%      defining the same alpha value for all pixels, or a 2D matrix
%
%  Outputs:
%    img - the resulting uint8 column vector in RGBA colour space
%    sz - the original size ([m n]) of the input image.  If the sizes of
%      colour and alpha differ, the size is defined as the maximum of both
%      dimentions
%
%  See also VIS.EMPTYLAYER, VIS.DRAW, VIS.RGBAFROMUINT8

% Save the size of the input image
h = max(size(colour, 1), size(alpha, 1));
w = max(size(colour, 2), size(alpha, 2));
sz = [w h];

% Recast values to uint8
% If all values are below 1, re-scale to be between 0 and 255
colour = uint8(iff(all(colour<=1), @()round(255*colour), colour));
alpha = uint8(iff(all(alpha<=1), @()round(255*alpha), alpha));

% If the overall luminance specified, replicate matrix for each colour
% channel
if ~isscalar(colour) && size(colour, 3) == 1
  colour = repmat(colour, [1, 1, 3]); % replicate to rgb
end


img = zeros(h, w, 4, 'uint8');

img(:,:,1:3) = colour;
img(:,:,4) = alpha;
img = permute(img, [3 2 1]);
img = img(:);
end