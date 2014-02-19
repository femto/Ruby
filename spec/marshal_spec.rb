require_relative "spec_helper"
require 'marshal1'
describe Marshal1 do
  it "should pass" do
    Marshal1.load("\004\b0").should == nil
  end
  it "should pass" do
    Marshal1.load("\004\bT").should == true
  end

  it "should pass" do
    Marshal1.load("\004\bF").should == false
  end

  it "raise exception" do
    lambda {Marshal1.load("\004\011T")}.should raise_error(Exception)
  end
end