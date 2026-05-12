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
  for i = 1:numel(results)
    fprintf('%s: Passed=%d Failed=%d\n', results(i).Name, results(i).Passed, results(i).Failed);
  end
  if all([results.Passed]); fprintf('TRANSFER TESTS OK\n'); end
catch e
  fprintf('TRANSFER TESTS FAILED: %s\n', e.message);
  disp(e.getReport('extended'));
end
try
  results = runtests('c:\Users\Work\source\repos\signalscpp\matlab\tests\Signals_test');
  for i = 1:numel(results)
    fprintf('%s: Passed=%d Failed=%d\n', results(i).Name, results(i).Passed, results(i).Failed);
  end
  if all([results.Passed]); fprintf('SIGNALS TESTS OK\n'); end
catch e
  fprintf('SIGNALS TESTS FAILED: %s\n', e.message);
  disp(e.getReport('extended'));
end
