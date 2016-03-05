From http://stackoverflow.com/questions/9998337/how-to-print-from-github --

Navigate to https://github.com/nellore/rail-dbgap/blob/master/README.md, and use the bookmarklet

        javascript:(function(e,a,g,h,f,c,b,d)%7Bif(!(f=e.jQuery)%7C%7Cg%3Ef.fn.jquery%7C%7Ch(f))%7Bc=a.createElement(%22script%22);c.type=%22text/javascript%22;c.src=%22http://ajax.googleapis.com/ajax/libs/jquery/%22+g+%22/jquery.min.js%22;c.onload=c.onreadystatechange=function()%7Bif(!b&&(!(d=this.readyState)%7C%7Cd==%22loaded%22%7C%7Cd==%22complete%22))%7Bh((f=e.jQuery).noConflict(1),b=1);f(c).remove()%7D%7D;a.documentElement.childNodes%5B0%5D.appendChild(c)%7D%7D)(window,document,%221.3.2%22,function($,L)%7B$('%23header,%20.pagehead,%20.breadcrumb,%20.commit,%20.meta,%20%23footer,%20%23footer-push,%20.wiki-actions,%20%23last-edit,%20.actions,%20.header,.site-footer,.repository-sidebar,.file-navigation,.gh-header-meta,.gh-header-actions,#wiki-rightbar,#wiki-footer,.commit-tease').remove();%20$('%23files,%20.file').css(%7B%22background%22:%22none%22,%20%22border%22:%22none%22%7D);%20$('link').removeAttr('media');%7D); var removeMe = document.getElementsByClassName("file-header")[0]; removeMe.parentNode.removeChild(removeMe);

Then print to PDF.
