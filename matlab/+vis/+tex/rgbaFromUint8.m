function [img, sz] = rgbaFromUint8(colour, alpha)
% VIS.RGBAFROMUINT8 Return the input image as a column vector in the form
% required by glTexImage2D along with its original size
%  Takes a matrix of uint8 values between 0 and 255 representing an image,
%  adds an alpha channel, permutes and vectorizes it.
%
%  Inputs:
%    colour - the image as either a 2D matrix of luminance values or a 3D
%      RGB matrix.  
%    alpha - the alpha values for the image.  May be either a scalar
%      defining the same alpha value for all pixels, or a 2D matrix
%
%    NB: All values must be 8-bit unsigned integers between 0 and 255
%
%  Outputs:
%    img - the resulting column vector in RGBA colour space
%    sz - the original size ([m n]) of the input image.  If the sizes of
%      colour and alpha differ, the size is defined as the maximum of both
%      dimentions
%
%  See also VIS.EMPTYLAYER, VIS.DRAW, VIS.RGBA

% Save the size of the input image
h = max(size(colour, 1), size(alpha, 1));
w = max(size(colour, 2), size(alpha, 2));
sz = [w h];

% If the overall luminance specified, replicate matrix for each colour
% channel
if ~isscalar(colour) && size(colour, 3) == 1 % overall luminance specified
  colour = repmat(colour, 1, 1, 3); % replicate to rgb
end

img = zeros(h, w, 4, 'uint8');

img(:,:,1:3) = colour;
img(:,:,4) = alpha;
img = permute(img, [3 2 1]);
img = img(:);

end