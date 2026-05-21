classdef Node_test < matlab.unittest.TestCase
  properties
    net
  end
  
  methods (TestClassSetup)
    function createNetwork(testCase)
      testCase.net = sig.Net;
      testCase.addTeardown(@delete, testCase.net)
    end
  end
    
  methods (Test)
    function test_Node_from(testCase)
      % Test for sig.Node.from method

      % Test behaviour when no inputs are Node or Signal objects
      testCase.verifyError(@() sig.Node.from(1, true, 'foo'), 'sig:node:noNet')

      % Test when Signal is in inputs
      s = testCase.net.origin('signal');
      nNodes = testCase.net.nActiveNodes;
      nodes = sig.Node.from(s, 1);
      testCase.verifyEqual(testCase.net.nActiveNodes, nNodes + 1)
      testCase.verifyTrue(isa(nodes(2), 'sig.Node'))
      testCase.verifyEqual(nodes(1), s.Node)

      % Test a Node object in inputs
      n = s.Node.from(nodes(1));
      testCase.verifyEqual(nodes(1), n)
    end

  end
end