#
#   ae-dir-projects.rb - Arcadia Ruby ide
#   by Antonio Galeone <antonio-galeone@rubyforge.org>
#
#   &require_dir_ref=../..
#   &require_omissis=conf/arcadia.init
#   &require_omissis=lib/a-commons
#   &require_omissis=lib/a-tkcommons
#   &require_omissis=lib/a-core



class Project
  attr_accessor :dir 
  attr_accessor :loaded 
  attr_reader :cache_dirs
  def initialize(_dir)
    @dir = _dir
    @loaded = false
    @cache_dirs = Array.new
  end
end

class DirProjects < ArcadiaExt
  include Autils
  attr_reader :htree

  def sync_on
    @sync = true
    select_file_without_event(@last_file) if @last_file
  end

  def sync_off
    @sync = false
  end

  def on_before_build(_event)
    Arcadia.attach_listener(self, BufferRaisedEvent)
    Arcadia.attach_listener(self, SaveAsBufferEvent)
  end

  def on_build(_event)
    @projects = Hash.new
    @node_parent = Hash.new
    @num_childrens_of = Hash.new
    @h_stack = Array.new
    @opened_folder = Array.new
    #--- button_box 
    @button_box = Tk::BWidget::ButtonBox.new(self.frame.hinner_frame){
      homogeneous true
      spacing 0
      padx 0
      pady 0
      background Arcadia.conf('panel.background')
    }.place('x'=>32,'height'=> 28)

    @button_box.add(Arcadia.style('toolbarbutton').update({
      'name'=>'new_proj',
      'anchor' => 'nw',
      'command'=>proc{self.do_new_project},
      'helptext'=>'New dir Project',
      'image'=> TkPhotoImage.new('dat' => NEW_GIF)})
    )

    @button_box.add(Arcadia.style('toolbarbutton').update({
      'name'=>'open_proj',
      'anchor' => 'nw',
      'command'=>proc{self.do_open_project},
      'helptext'=>'Open dir as Project',
      'image'=> TkPhotoImage.new('dat' => OPEN_GIF)})
    )
    #--- button_box
    
    @cb_sync = TkCheckButton.new(self.frame.hinner_frame, Arcadia.style('checkbox')){
      text  'Sync'
      justify  'left'
      indicatoron 0
      offrelief 'raised'
      image TkPhotoImage.new('dat' => SYNCICON20_GIF)
      #pack('anchor'=>'n')
      place('x' => 0,'y' => 0,'height' => 26)
    }

    Tk::BWidget::DynamicHelp::add(@cb_sync, 
      'text'=>'Link open editors with content in the Navigator')

    do_check = proc {
      if @cb_sync.cget('onvalue')==@cb_sync.cget('variable').value.to_i
        sync_on
      else
        sync_off
      end
    }
    @sync = false
    @cb_sync.command(do_check)
    @font =  Arcadia.conf('treeitem.font')
    @font_b = "#{Arcadia.conf('treeitem.font')} bold"
    @selecting_node = false    
    do_select_item = proc{|_tree, _selected|
      if File.exist?(node2file(_selected))
        if File.ftype(node2file(_selected)) == 'file'
          _sync_val = @sync
          @sync = false
          begin
  	         Arcadia.process_event(OpenBufferTransientEvent.new(self,'file'=>node2file(_selected)))
  	       ensure
            @sync = _sync_val
  	       end
#        elsif !_selected.nil? && @htree.open?(node2file(_selected))
#          @htree.close_tree(node2file(_selected))
#        elsif !_selected.nil?
#          @htree.open_tree(node2file(_selected),false) 
        end
      else
        shure_delete_node(_selected)
      end
    }
    
    
    do_open_folder_cmd = proc{|_node| do_open_folder(_node)}
    do_close_folder_cmd = proc{|_node| do_close_folder(_node)}
    
#	  @htree = Tk::BWidget::Tree.new(self.frame.hinner_frame, Arcadia.style('treepanel')){
	  @htree = Tk::BWidget::Tree.new(self.frame.hinner_frame, Arcadia.style('treepanel')){
      showlines false
      deltay 18
      opencmd do_open_folder_cmd
      closecmd do_close_folder_cmd
      selectcommand do_select_item
    }
    
    class << @htree
      def open?(node)
        bool(self.itemcget(tagid(node), 'open'))
      end
    
      def areabind(context, *args)
        if TkComm._callback_entry?(args[0]) || !block_given?
          cmd = args.shift
        else
          cmd = Proc.new
        end
        _bind_for_event_class(Event_for_Items, [path, 'bindArea'], 
                              context, cmd, *args)
        self
      end
    
      def areabind_append(context, *args)
        if TkComm._callback_entry?(args[0]) || !block_given?
          cmd = args.shift
        else
          cmd = Proc.new
        end
        _bind_append_for_event_class(Event_for_Items, [path, 'bindArea'], 
                                     context, cmd, *args)
        self
      end
    
      def areabind_remove(*args)
        _bind_remove_for_event_class(Event_for_Items, [path, 'bindArea'], *args)
        self
      end
    
      def areabindinfo(*args)
        _bindinfo_for_event_class(Event_for_Items, [path, 'bindArea'], *args)
      end
    end
    _wrapper = TkScrollWidget.new(@htree)  
    _wrapper.show(0,26)
    _wrapper.show_v_scroll
    _wrapper.show_h_scroll
    self.pop_up_menu_tree
    @image_kdir = TkPhotoImage.new('dat' => ICON_FOLDER_OPEN_GIF)
    @image_kdir_closed = TkPhotoImage.new('dat' => FOLDER_GIF)
	  self.load_projects
    @htree.areabind_append('KeyPress',proc{|k| 
        key_press(k)
    },"%K")

    do_double_click = proc{
        _selected = @htree.selection_get[0]
        if File.ftype(node2file(_selected)) == 'directory'
          if !_selected.nil? && @htree.open?(node2file(_selected))
            @htree.close_tree(node2file(_selected))
          elsif !_selected.nil?
            @htree.open_tree(node2file(_selected),false) 
          end
        end
    }
    
    @htree.textbind_append('Double-1',do_double_click)
	end
	
	def key_press(_keysym)
      case _keysym
        when 'F5'
        _selected = self.selected
        do_refresh(_selected)
      end
	end

	def on_after_build(_event)
    self.frame.show
	end

  def node2file(_node)
    if _node[0..0]=='{' && _node[-1..-1]=='}'
      return _node[1..-2]
    else
      return _node
    end
  end

  def file2node(_file)
    if _file.include?("\s") && _file[0..0]!='{'
      return "{#{_file}}"
    else
      return _file
    end
  end  

  def do_close_folder(_node, _close=false)
    @opened_folder.delete(_node)
    @htree.close_tree(_node) if _close
  end

  def do_open_folder(_node, _open=false)
    proj  = @projects[_node]
    if proj && !proj.loaded
      n = load_tree_from_dir(_node)
      proj.loaded = true
    else
      proj = project_of_node(_node)
      if !proj.cache_dirs.include?(_node)
        load_tree_from_dir(_node)
        proj.cache_dirs << _node
      end
      if @num_childrens_of[_node] == 1
        child = @htree.nodes(_node)[0]
        if File.ftype(node2file(child)) == 'directory'
          @htree.open_tree(child,false) 
          @opened_folder << child if !@opened_folder.include?(child)
        end
#      elsif @num_childrens_of[_node] > 1
#        @htree.nodes(_node).each{|child|
#          if @opened_folder.include?(child)
#            load_tree_from_dir(child)
#            do_open_folder(child, true)
#          end
#        }
      end
    end
    @opened_folder << _node if !@opened_folder.include?(_node)
    @htree.open_tree(_node,false)  if _open
  end

  def load_tree_from_dir(_node, _reset = false)
    @htree.delete(@htree.nodes(_node)) if _reset
    if @htree.exist?(_node)
      childrens = Dir.entries(node2file(_node))
      childrens_dir = Array.new
      childrens_file = Array.new
      @num_childrens_of[_node] = childrens.length-2
      childrens.sort.each{|c|
        if c != '.' && c != '..'
          child = File.join(node2file(_node),c)
          fty = File.ftype(node2file(child))
          if fty == "file"
            childrens_file << child
            #add_node(_node, child, fty)
          elsif fty == "directory"
            childrens_dir << child
            #add_node(_node, child, fty)
          end
        end
      }
      childrens_dir.each{|child|
        add_node(_node, child, "directory")
      }
      childrens_file.each{|child|
        add_node(_node, child, "file")
      }
    end
  end

  def pop_up_menu_tree
    @pop_up_tree = TkMenu.new(
      :parent=>@htree,
      :tearoff=>0,
      :title => 'Menu tree'
    )
    @pop_up_tree.configure(Arcadia.style('menu'))
    #----- new submenu
    sub_new = TkMenu.new(
      :parent=>@pop_up,
      :tearoff=>0,
      :title => 'New'
    )
    sub_new.configure(Arcadia.style('menu'))
    sub_new.insert('end',
      :command,
      :label=>'New dir Project',
      :hidemargin => false,
      :command=> proc{do_new_project}
    )

    sub_new.insert('end',
      :command,
      :label=>'New folder',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          do_new_folder(_selected)
        end
      }
    )

    sub_new.insert('end',
      :command,
      :label=>'New file',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          do_new_file(_selected)
        end
      }
    )

    @pop_up_tree.insert('end',
      :cascade,
      :label=>'New',
      :menu=>sub_new,
      :hidemargin => false
    )
    #-----------------
    #----- refactor submenu
    sub_ref = TkMenu.new(
      :parent=>@pop_up,
      :tearoff=>0,
      :title => 'Ref'
    )
    sub_ref.configure(Arcadia.style('menu'))
    sub_ref.insert('end',
      :command,
      :label=>'Rename',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          do_rename(_selected)
        end
      }
    )
    sub_ref.insert('end',
      :command,
      :label=>'Move',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          _idir = File.split(_selected)[0]
          _dir=Tk.chooseDirectory('initialdir'=>_idir,'mustexist'=>true) 
          do_move(_selected, _dir) if _dir && File.exists?(_dir)
        end
      }
    )
    @pop_up_tree.insert('end',
      :cascade,
      :label=>'Refactor',
      :menu=>sub_ref,
      :hidemargin => false
    )
    
    
    #-----------------
    #----- search submenu
    sub_ref_search = TkMenu.new(
      :parent=>@pop_up,
      :tearoff=>0,
      :title => 'Ref'
    )
    sub_ref_search.configure(Arcadia.style('menu'))
    sub_ref_search.insert('end',
      :command,
      :label=>'Find in files...',
      :hidemargin => false,
      :command=> proc{
        _target = self.selected
        if _target
          _target = File.dirname(_target) if File.ftype(_target) == 'file'
          Arcadia.process_event(SearchInFilesEvent.new(self,'dir'=>_target))
        end
      }
    )
    
    sub_ref_search.insert('end',
      :command,
      :label=>'Act in files...',
      :hidemargin => false,
      :command=> proc{
        _target = self.selected
        if _target
          _target = File.dirname(_target) if File.ftype(_target) == 'file'
          Arcadia.process_event(AckInFilesEvent.new(self,'dir'=>_target))
        end
      }
    )
    @pop_up_tree.insert('end',
      :cascade,
      :label=>'Search from here',
      :menu=>sub_ref_search,
      :hidemargin => false
    )
    
    
    #-----------------
    
    @pop_up_tree.insert('end',
      :command,
      :label=>'Open dir as Project',
      :hidemargin => false,
      :command=> proc{do_open_project}
    )
    @pop_up_tree.insert('end',
      :command,
      :label=>'Close Project',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          #p _selected
          do_close_project(_selected)
        end
      }
    )
    @pop_up_tree.insert('end',
      :command,
      :label=>'Refresh',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        do_refresh(_selected)
      }
    )
    @pop_up_tree.insert('end',
      :command,
      :label=>'Delete',
      :hidemargin => false,
      :command=> proc{
        _selected = self.selected
        if _selected
          do_delete(_selected)
        end
      }
    )
    @htree.areabind_append("Button-3",
      proc{|x,y|
        _x = TkWinfo.pointerx(@htree)
        _y = TkWinfo.pointery(@htree)
        @pop_up_tree.popup(_x,_y)
      },
    "%x %y")
  end

  def selected
    if @htree.selection_get[0]
      if @htree.selection_get[0].length >0
       	_selected = ""
        if String.method_defined?(:lines)
      	   selection_lines = @htree.selection_get[0].lines
        else
      	   selection_lines = @htree.selection_get[0].split("\n")
        end
        selection_lines.each{|_block|
          _selected = _selected + _block.to_s + "\s" 
        }
        _selected = _selected.strip
      else
        _selected = @htree.selection_get[0]
      end
    end
    return _selected
  end

  def do_new_project(_parent_folder_node=nil)
    if _parent_folder_node.nil?
      _parent_folder_node=Tk.chooseDirectory 'initialdir' =>  MonitorLastUsedDir.get_last_dir
    end
    if _parent_folder_node && File.exists?(node2file(_parent_folder_node)) && File.ftype(node2file(_parent_folder_node)) == 'directory'
      tmp_node_name = "#{node2file(_parent_folder_node)}#{File::SEPARATOR}_new_project_"
      tree_parent = _parent_folder_node
      add_temp_node('root',tmp_node_name,'project')
      _verify_cmd = proc{|_text|
        _ret = 0
        begin
          new_dir_name = "#{_parent_folder_node}#{File::SEPARATOR}#{_text}"
          if !File.exists?(new_dir_name)
            Dir.mkdir(new_dir_name)
            add_project(new_dir_name)
          end
          _ret = 1
        ensure
          @htree.delete(file2node(tmp_node_name))
        end
        _ret
      }
#      @htree.textbind('KeyPress', proc{|e| 
#      p 'pippo'})
      @htree.edit(tmp_node_name, tmp_node_name.split(File::SEPARATOR)[-1], _verify_cmd, 1)
    end

  end
  
  def do_open_project(_proj_name=nil)
    if _proj_name.nil?
      _proj_name=Tk.chooseDirectory 'initialdir' =>  MonitorLastUsedDir.get_last_dir
      add_project(_proj_name) if _proj_name && File.exists?(_proj_name)
    end
  end

  def do_close_project(_proj_name)
    if _proj_name && is_project?(_proj_name)
      del_project(_proj_name)
    end
  end

  def do_new_folder(_parent_folder_node)
    if File.exists?(node2file(_parent_folder_node)) && File.ftype(node2file(_parent_folder_node)) == 'directory'
      tmp_node_name = "#{node2file(_parent_folder_node)}#{File::SEPARATOR}_new_folder_"
      add_temp_node(_parent_folder_node,tmp_node_name,'directory')
      @htree.open_tree(_parent_folder_node,false)
      _verify_cmd = proc{|_text|
        _ret = 0
        begin
          new_dir_name = "#{node2file(_parent_folder_node)}#{File::SEPARATOR}#{_text}"
          if !File.exists?(new_dir_name)
            Dir.mkdir(new_dir_name)
            add_node(_parent_folder_node,new_dir_name,'directory')
          end
          _ret = 1
        ensure
          @htree.delete(file2node(tmp_node_name))
          shure_select_node(new_dir_name)
        end
        _ret
      }
      @htree.edit(tmp_node_name, tmp_node_name.split(File::SEPARATOR)[-1], _verify_cmd, 1)
    end
  end

  def do_new_file(_parent_folder_node)
    if File.exists?(node2file(_parent_folder_node)) && File.ftype(node2file(_parent_folder_node)) == 'directory'
      tmp_node_name = "#{node2file(_parent_folder_node)}#{File::SEPARATOR}_new_file_"
      add_temp_node(_parent_folder_node,tmp_node_name,"file")
      @htree.open_tree(_parent_folder_node,false)
      _verify_cmd = proc{|_text|
        _ret = 0
        begin
          new_file_name = "#{node2file(_parent_folder_node)}#{File::SEPARATOR}#{_text}"
          if !File.exists?(new_file_name)
            File.new(new_file_name, "w").close
            add_node(_parent_folder_node,new_file_name,"file")
            #Arcadia.process_event(OpenBufferEvent.new(self,'file'=>_node))
          end
          _ret = 1
        ensure
          @htree.delete(file2node(tmp_node_name))
        end
        _ret
      }
      @htree.edit(tmp_node_name, tmp_node_name.split(File::SEPARATOR)[-1], _verify_cmd, 1)
    end
  end

  def do_refresh(_node)
    if _node.nil?
      @projects.keys.each{|proj|
        if !File.exists?(proj)
          del_project(proj)
        else
          do_refresh(proj)
        end
      }
    elsif @htree.exist?(_node)
      opened = @opened_folder.include?(_node)
      @htree.close_tree(_node)
      nodes = @htree.nodes(_node)
      shure_delete_node(nodes) if nodes
      proj  = @projects[_node]
      if proj && proj.loaded
        proj.loaded = false
        proj.cache_dirs.clear
      else
        proj = project_of_node(_node)
        if proj
          proj.cache_dirs.delete(_node)
        end
      end
      do_open_folder(_node, opened) if opened
      nodes.each{|n|
        if File.exists?(n) && File.ftype(node2file(n)) == 'directory'
          do_refresh(n)
        end
      }
    end
  end

  def do_move(_source, _destination, _interactive = true)
    _msg = "Move #{_source} to #{_destination}?"
    if !_interactive || Arcadia.dialog(self,'type'=>'yes_no', 'level'=>'warning','title' => 'Confirm move', 'msg'=>_msg)=='yes'
      if File.exists?(_source) 
        type = File.ftype(node2file(_source))
        source_basename = _source.split(File::SEPARATOR)[-1]
        if type == 'directory'
          des_path = File.join(_destination,source_basename)
          if File.exists?(des_path)  || Dir.mkdir(des_path)
            entries = Dir.entries(_source)
            entries.delete('.')
            entries.delete('..')
            entries.each{|en|
              full_en = File.join(_source,en)
              do_move(full_en, des_path, false)
            }
            Dir.delete(_source)
            if @projects[_source]
              del_project(_source)
            end
          end
        else
          new_file = File.join(_destination,source_basename)
          if File.rename(_source, new_file)
            # evento
            Arcadia.process_event(MoveBufferEvent.new(self,'old_file'=>_source,'new_file'=>new_file))
          end
        end
        if _interactive
          do_refresh(File.split(_source)[0])
          do_refresh(_destination)
        end
      end
    end
  end

  def do_rename(_source)
    old_file_name = node2file(_source)
    if File.exists?(old_file_name) 
      source_dir = File.split(old_file_name)[0]
      _verify_cmd = proc{|_text|
        _ret = 0
        begin
          new_file_name = "#{source_dir}#{File::SEPARATOR}#{_text}"
          #p "new_file_name=#{new_file_name}"
          #p "old_file_name=#{old_file_name}"
          if !File.exists?(new_file_name)
            if File.rename(old_file_name, new_file_name)
              # evento
              Arcadia.process_event(MoveBufferEvent.new(self,'old_file'=>old_file_name,'new_file'=>new_file_name))
            end
          end
          _ret = 1
        ensure
          shure_delete_node(_source)
          do_refresh(source_dir)
        end
        _ret
      }
      @htree.edit(_source, _source.split(File::SEPARATOR)[-1], _verify_cmd, 1)
    end
  end

  def is_project?(_node)
    @htree.exist?(_node) && @htree.parent(_node)=='root'
  end

  def do_delete(_node, _interactive = true)
    if File.exists?(node2file(_node)) 
      type = File.ftype(node2file(_node))
      if type == 'directory'
        _msg = "Delete #{_node} directory ?"
      else
        _msg = "Delete #{_node} file ?"
      end
      if !_interactive || Arcadia.dialog(self,'type'=>'yes_no', 'level'=>'warning','title' => 'Confirm delete', 'msg'=>_msg)=='yes'
        delete_node = true
        if type == 'directory'
          entries = Dir.entries(node2file(_node))
          entries.delete('.')
          entries.delete('..')
          #is_project = @htree.exist?(_node) && @htree.parent(_node)=='root'
          if entries.length > 0
            _msg2 = "#{_node} isn't empty. Shure to delete all sub entries ?"
            entries.each{|en|
              _msg2 = "#{_msg2}\n#{en}"
            }
            if !_interactive || Arcadia.dialog(self,'type'=>'yes_no', 'level'=>'warning','title' => 'Confirm deletion', 'msg'=>_msg2)=='yes'
              entries.each{|en|
                do_delete(File.join(node2file(_node),en),false)
              }
              Dir.delete(node2file(_node))
            else
              delete_node = false
            end
          else
            Dir.delete(node2file(_node))
          end
          if  is_project?(_node) && delete_node
            delete_node = false
            del_project(_node)
          end
        else
          Arcadia.process_event(CloseBufferEvent.new(self,'file'=>node2file(_node)))
          File.delete(node2file(_node))
        end
        shure_delete_node(_node) if delete_node
      end
    end
  end

  def project_of_node(_node)
    project = _node
    while !@node_parent[project].nil? && @node_parent[project] != 'root'
      project = @node_parent[project]
    end
    return @projects[project]
  end

  def add_node(_parent, _node, _kind)
    return if @htree.exist?(_node)
    @node_parent[_node] = _parent
    _name = _node.split(File::SEPARATOR)[-1]
    _drawcross = 'auto'
    if _kind == "project" || _kind == "directory"
      num = Dir.entries(_node).length-2
      if num > 0
        _drawcross = 'always'
      end
    end
    @htree.insert('end', _parent ,_node, {
      'text' =>  _name ,
      'helptext' => _node,
      'drawcross'=>_drawcross,
      'deltax'=>-1,
      'image'=> image(_kind, _node)
    }.update(Arcadia.style('treeitem'))
    )
    if _kind == "project" || _kind == "directory"
      if @opened_folder.include?(_node)
        do_open_folder(_node, true)
      end
    end
  end

  def add_temp_node(_parent, _node, _kind)
    return if @htree.exist?(_node)
    _name = _node.split(File::SEPARATOR)[-1]
    _drawcross = 'auto'
    @htree.insert('end', _parent ,_node, {
      'text' =>  _name ,
      'helptext' => _node,
      'drawcross'=>_drawcross,
      'deltax'=>-1,
      'image'=> image(_kind, _node)
    }.update(Arcadia.style('treeitem'))
    )
  end

  def add_project(_dir)
    @projects[_dir] = Project.new(_dir)
    add_node('root', _dir, "project")
    add_project_to_file(_dir) 
  end

  def shure_delete_node(_node)
    if _node.length>1 || @htree.exist?(_node)
      _sc = @htree.cget('selectcommand')
      begin
        @htree.configure('selectcommand'=>nil)
        @htree.delete(file2node(_node))
      ensure
        @htree.configure('selectcommand'=>_sc)
      end
    end
  end

  def shure_select_node(_node)
    return if @selecting_node
    @selecting_node = true
    _proc = @htree.selectcommand
    @htree.selectcommand(nil)
    begin
      @htree.selection_clear
      @htree.selection_add(_node)
      @htree.see(_node)
    ensure
      @htree.selectcommand(_proc)
      @selecting_node = false
    end
  end

  def del_project(_dir)
      shure_delete_node(file2node(_dir))
      @projects.delete(_dir)
      del_project_from_file(_dir) 
  end


  def load_projects
    f = File::open(projects_file,'r')
    begin
      _lines = f.readlines.collect!{| line | line.chomp}
    ensure
      f.close unless f.nil?
    end
    _lines.each{|_line|
      if _line.length > 0 && _line[0] != '#' && FileTest.directory?(_line)
        add_project(_line)
      end
    }
  end
	
	def add_project_to_file(_project)
    f = File::open(projects_file,'r')
    begin
      _lines = f.readlines.collect!{| line | line.chomp}
    ensure
      f.close unless f.nil?
    end
    if !_lines.include?(_project)
      f = File.new(projects_file, "w")
      begin
        _lines.each{|_line|
          f.syswrite(_line+"\n")
        }
        f.syswrite(_project+"\n")
      ensure
        f.close unless f.nil?
      end
    end	
	end

	def del_project_from_file(_project)
	 # p "del_project_from_file =>#{_project}"
	 # p projects_file
    f = File::open(projects_file,'r')
    begin
      _lines = f.readlines.collect!{| line | line.chomp}
    ensure
      f.close unless f.nil?
    end
    f = File.new(projects_file, "w")
    begin
      _lines.each{|_line|
        if _line != _project
        p _line
          f.syswrite(_line+"\n")
        end
      }
    ensure
      f.close unless f.nil?
    end
	end

	
	def projects_file
    if !defined?(@arcadia_projects_file)
    		@arcadia_projects_file = @arcadia.local_dir+'/'+conf('file.name')
    		if !File.exist?(@arcadia_projects_file)
     			dir,fil =File.split(File.expand_path(@arcadia_projects_file))
     			if !File.exist?(dir)
     			  Dir.mkdir(dir)
     			end
        f = File.new(@arcadia_projects_file, "w+")
        begin
          f.syswrite("#Projects conf\n") if f
        ensure
          f.close unless f.nil?
        end
      end
    		
    end
    return @arcadia_projects_file
	end


  def select_file_without_event(_file)
    _file_node_rif = File.expand_path(_file)
    steps = _file_node_rif.split(File::SEPARATOR)
    j = 0
    max = steps.length-1
    path = ''
    while j <  max
      if path.strip.length > 0 && path.strip != File::SEPARATOR
        path = path + File::SEPARATOR
      end
      if path.strip.length == 0 && _file_node_rif[0..0] == File::SEPARATOR
        path = File::SEPARATOR
      end
      path = path + steps[j]
      if @htree.exist?(path) 
        @htree.open_tree(path, false)
      end
      j=j+1
    end
    if @htree.exist?(_file_node_rif)
      shure_select_node(_file_node_rif)
    end
  end
		
  def on_buffer_raised(_event)
    return if _event.file.nil?
    @last_file = _event.file
    if @sync
      select_file_without_event(_event.file)
    end
  end
  
  def on_before_save_as_buffer(_event)
    _selected = self.selected
    if _selected
      tpy =  File.ftype(node2file(_selected))
      if tpy == 'directory'
        Dir.chdir(_selected)
      elsif tpy == 'file'
        Dir.chdir(File.dirname(_selected))
      end      
    end
  end

  def image(_kind, _label='.rb')
      if _kind == 'directory'
        return @image_kdir
      elsif _kind == 'project'
        return @image_kdir_closed
      elsif _kind == 'file'
        return Arcadia.file_icon(_label)
      end

#      elsif _kind == 'file' && _label.include?('.rb')
#        return @image_kfile_rb
#      else
#        return @image_kfile
#      end
  end


end