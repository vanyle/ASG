/// Tests that ASG is able to compile blogs properly.
///
use std::path::{self, Path};

#[tokio::test]
async fn it_compiles_blogs() {
    let input_directory = path::absolute(Path::new("tests/blog_light_theme/src")).unwrap();
    let output_directory = path::absolute(Path::new("tests/blog_light_theme/build")).unwrap();
    let asset_directory = path::absolute(Path::new("assets")).unwrap();

    asg::compile_without_server(&input_directory, &output_directory, Some(asset_directory)).await;
}

#[tokio::test]
async fn it_generates_documentation() {
    let input_directory = path::absolute(Path::new("tests/documentation/src")).unwrap();
    let output_directory = path::absolute(Path::new("tests/documentation/build")).unwrap();
    let asset_directory = path::absolute(Path::new("assets")).unwrap();

    asg::compile_without_server(&input_directory, &output_directory, Some(asset_directory)).await;
}

#[tokio::test]
async fn it_renders_graphics() {
    let input_directory = path::absolute(Path::new("tests/graphics/src")).unwrap();
    let output_directory = path::absolute(Path::new("tests/graphics/build")).unwrap();
    let asset_directory = path::absolute(Path::new("assets")).unwrap();

    asg::compile_without_server(&input_directory, &output_directory, Some(asset_directory)).await;
}
