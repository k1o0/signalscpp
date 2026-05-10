addpath('c:\Users\Work\source\repos\signalscpp\matlab');
try
  run('c:\Users\Work\source\repos\signalscpp\matlab\tests\smoke_test');
  fprintf('SMOKE TESTS OK\n');
catch e
  fprintf('SMOKE TESTS FAILED: %s\n', e.message);
end
try
  run('c:\Users\Work\source\repos\signalscpp\matlab\tests\node_test');
  fprintf('NODE TESTS OK\n');
catch e
  fprintf('NODE TESTS FAILED: %s\n', e.message);
end
try
  results = runtests('c:\Users\Work\source\repos\signalscpp\matlab\tests\transfer_test');
  t = struct2table([struct(results)]); disp(t(:,{'Name','Passed','Failed'}));
catch e
  fprintf('TRANSFER TESTS FAILED: %s\n', e.message);
  disp(e.getReport('extended'));
end
