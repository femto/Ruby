require "e2mmap"
require "pry/notifier"
module Pry
  class SLex

    DOUT = Notifier::def_notifier("SLex::")
    D_WARN = DOUT::def_notifier(1, "Warn: ")
    D_DEBUG = DOUT::def_notifier(2, "Debug: ")
    D_DETAIL = DOUT::def_notifier(4, "Detail: ")

    DOUT.level = 4
    #DOUT.level = Notifier::D_NOMSG

    def initialize
      @head = Node.new("")
    end

    def def_rules(*tokens, &block)
      if block_given?
        p = block
      end
      for token in tokens
        def_rule(token, nil, p)
      end
    end

    def def_rule(token, preproc = nil, postproc = nil, &block)
      D_DETAIL.pp token

      postproc = block if block_given?
      create(token, preproc, postproc)
    end

    def create(token, preproc = nil, postproc = nil)
      @head.create_subnode(token.split(//), preproc, postproc)
    end

    class Node
      # if postproc is nil, this node is an abstract node.
      # if postproc is non-nil, this node is a real node.
      def initialize(preproc = nil, postproc = nil)
        @Tree = {}
        @preproc = preproc
        @postproc = postproc
      end

      attr_accessor :preproc
      attr_accessor :postproc

      def create_subnode(chrs, preproc = nil, postproc = nil)
        if chrs.empty?
          if @postproc
            D_DETAIL.pp node
            SLex.fail ErrNodeAlreadyExists
          else
            D_DEBUG.puts "change abstract node to real node."
            @preproc = preproc
            @postproc = postproc
          end
          return self
        end

        ch = chrs.shift
        if node = @Tree[ch]
          if chrs.empty?
            if node.postproc
              DebugLogger.pp node
              DebugLogger.pp self
              DebugLogger.pp ch
              DebugLogger.pp chrs
              SLex.fail ErrNodeAlreadyExists
            else
              D_WARN.puts "change abstract node to real node"
              node.preproc = preproc
              node.postproc = postproc
            end
          else
            node.create_subnode(chrs, preproc, postproc)
          end
        else
          if chrs.empty?
            node = Node.new(preproc, postproc)
          else
            node = Node.new
            node.create_subnode(chrs, preproc, postproc)
          end
          @Tree[ch] = node
        end
        node
      end
    end
  end
end