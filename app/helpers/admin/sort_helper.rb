module Admin::SortHelper
  def sort_link(title, key)
    current_sort = params[:sort].to_s
    current_dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'

    next_dir = (current_sort == key.to_s && current_dir == 'asc') ? 'desc' : 'asc'
    icon = nil
    if current_sort == key.to_s
      icon = current_dir == 'asc' ? 'fa-sort-up' : 'fa-sort-down'
    else
      icon = 'fa-sort'
    end

  link_to({ sort: key, dir: next_dir, page: 1 }.merge(request.query_parameters.except(:sort, :dir, :page))) do
      %Q(<span>#{ERB::Util.html_escape(title)}</span> <i class="fa #{icon} ms-1 text-muted"></i>).html_safe
    end
  end
end
