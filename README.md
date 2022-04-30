# github-statistics
**github-statistics** is a workflow repository designed to pull data from the
[GitHub Users API][1] on a regularly scheduled basis to generate distribution
statistics based on a subset of GitHub early users.

The planned studies to be produced by this repository will be bounded by GitHub
repository limits in order to follow recommendations set out by the
[Managing large files][2] article.

**Note:** [Do not use Git LFS.][3] It is not possible to remove Git LFS objects
from a repository without deleting and recreating the repository. 

## Databases
* `github-users.db`  

### Tables
* `users`
  The first 1.5 million GitHub users as listed by `GET /users`
* `users_followers`
  The first 22,500 GitHub users from `users` and their follower counts

## Decompress database
### macOS
```sh
zstd -d github-users.tzst
tar xf github-users.tar
```

### Ubuntu
```sh
tar --use-compress-program zstd -xf github-users.tzst
```

## License
GNU General Public License v2.0

[1]: https://docs.github.com/en/rest/users/users
[2]: https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github
[3]: https://docs.github.com/en/repositories/working-with-files/managing-large-files/removing-files-from-git-large-file-storage#git-lfs-objects-in-your-repository
